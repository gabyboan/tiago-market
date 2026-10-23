#!/usr/bin/env python3
"""Prepare, dry-run and publish bounded batches through existing Dart staging.

No schema changes. Default prepares SQL and executes rollback-only checks. An
explicit --publish reuses that verified manifest, checks hashes and fresh dates,
then commits each chunk. Re-running the same observations is idempotent.
"""
import argparse
from datetime import datetime, timedelta, timezone
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
from uuid import UUID

from expand_grocery_sources import SOURCES
from online_catalog import timestamp
from refresh_grocery_catalogs import json_write
from refresh_online_catalog import Database, literal, ROOT
from catalog_storage import CAPACITY_GUARD, cleanup_sql, execute_report


def registration_sql(sources=None):
    sql=[]
    for priority,source in enumerate(('superissste-mx','merkabastos-mx'),36):
        if sources is not None and source not in sources:continue
        host,_,brand=SOURCES[source]
        values=[literal(source),literal('MX'),literal(brand),literal('supermercado'),literal('online'),
                'false',str(priority),literal('validated'),literal(host),literal(f'https://{host}/robots.txt'),
                literal('Official public catalog: explicit MXN price, product images where supplied and online availability. No verified branch, physical stock reservation or partner agreement.')]
        sql.append('insert into ingestion.source_catalog (source_slug,country_code,store_brand,vertical,capture_scope,geolocatable,priority,status,official_domain,robots_url,notes) values ('+
                   ','.join(values)+') on conflict (source_slug) do update set capture_scope=excluded.capture_scope,geolocatable=excluded.geolocatable,status=excluded.status,official_domain=excluded.official_domain,robots_url=excluded.robots_url,notes=excluded.notes,updated_at=now();')
    return '\n'.join(sql)+'\n'


def ingestion_result(stdout):
    # stage_ndjson first returns set_config(run_id), then the JSON report.
    # The Management API exposes only the final result; psql emits both.
    output=stdout.strip()
    first,separator,remaining=output.partition('\n')
    if separator:
        try:
            UUID(first.strip())
        except ValueError:
            pass
        else:
            output=remaining.strip()
    doc=json.loads(output)
    value=doc['rows'][0]['ingestion_report'] if isinstance(doc,dict) and 'rows' in doc else doc
    result=json.loads(value) if isinstance(value,str) else value
    if not isinstance(result,dict) or not isinstance(result.get('publishable'),int):
        raise ValueError('Missing ingestion publication report')
    return result


def file_hash(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--input',type=Path,required=True)
    p.add_argument('--out-dir',type=Path,required=True)
    p.add_argument('--run-source',default='groceries-full-refresh-20261012')
    p.add_argument('--dart',default=shutil.which('dart') or 'dart')
    p.add_argument('--publish',action='store_true')
    args=p.parse_args()
    if args.publish:
        manifest=json.loads((args.out_dir/'manifest.json').read_text())
        if not manifest['dry_run_passed'] or file_hash(args.input)!=manifest['input_sha256']:
            raise RuntimeError('Successful dry-run and identical input are required')
    else:
        args.out_dir.mkdir(parents=True,exist_ok=False)
        raw=[line for line in args.input.read_text().splitlines() if line.strip()]
        chunks,current,size=[],[],0
        for line in raw:
            length=len(line.encode())
            if current and (len(current)>=400 or size+length>1500000):
                chunks.append(current);current=[];size=0
            current.append(line);size+=length
        if current:chunks.append(current)
        manifest={'input_sha256':file_hash(args.input),'rows':len(raw),'chunks':[],
                  'dry_run_passed':False,'published':False,'run_source':args.run_source}
        register=registration_sql({json.loads(line)['source'] for line in raw});(args.out_dir/'register-sources.sql').write_text(register)
        for number,chunk in enumerate(chunks,1):
            folder=args.out_dir/f'chunk-{number:03}';folder.mkdir()
            ndjson=folder/'input.ndjson';ndjson.write_text('\n'.join(chunk)+'\n')
            command=[args.dart,'run','tools/ingestion/bin/stage_ndjson.dart','--input',str(ndjson),
                     '--run-source',args.run_source,'--sql-out',str(folder/'generated.sql'),
                     '--json-report',str(folder/'preflight.json'),'--report-out',str(folder/'preflight.txt')]
            result=subprocess.run(command,cwd=ROOT,text=True,capture_output=True,timeout=120)
            (folder/'preflight.log').write_text(result.stdout+'\n'+result.stderr)
            if result.returncode:raise RuntimeError(f'Preflight failed in chunk {number}')
            preflight=json.loads((folder/'preflight.json').read_text())
            if preflight['publishable']!=len(chunk) or preflight['rejected'] or preflight['duplicate_input_records']:
                raise RuntimeError(f'Invalid batch in chunk {number}')
            generated=(folder/'generated.sql').read_text()
            if generated.count('begin;')!=1 or not generated.rstrip().endswith('commit;'):
                raise RuntimeError('Unexpected transaction shape')
            sql=generated.replace('begin;','begin;\n'+CAPACITY_GUARD+register,1)
            (folder/'publish.sql').write_text(sql)
            (folder/'dry-run.sql').write_text(sql.rsplit('commit;',1)[0]+'rollback;\n')
            manifest['chunks'].append({'number':number,'rows':len(chunk),'sql_sha256':file_hash(folder/'publish.sql')})
            print(json.dumps({'prepared_chunk':number,'rows':len(chunk)}),flush=True)
        json_write(args.out_dir/'manifest.json',manifest)
    dbfolder=args.out_dir/('publication' if args.publish else 'dry-run');dbfolder.mkdir(exist_ok=True)
    db=Database(dbfolder);reports=[]
    for chunk in manifest['chunks']:
        number=chunk['number'];folder=args.out_dir/f'chunk-{number:03}'
        if file_hash(folder/'publish.sql')!=chunk['sql_sha256']:
            raise RuntimeError('Prepared SQL hash mismatch')
        # Validate original capture dates again immediately before committing.
        if args.publish:
            for line in (folder/'input.ndjson').read_text().splitlines():
                at=timestamp(json.loads(line)['captured_at']);now=datetime.now(timezone.utc)
                if not now-timedelta(days=7)<at<=now+timedelta(minutes=5):
                    raise RuntimeError('Capture is no longer fresh; rerun the scraper')
        path=folder/('publish.sql' if args.publish else 'dry-run.sql')
        report=ingestion_result(db.execute(path.read_text(),f'chunk-{number:03}'))
        json_write(folder/('publication-report.json' if args.publish else 'dry-run-report.json'),report)
        if report['publishable']!=chunk['rows'] or report['rejected_local']:
            raise RuntimeError(f'Unexpected publication eligibility in chunk {number}')
        reports.append(report)
        if args.publish:
            rows=[json.loads(line) for line in (folder/'input.ndjson').read_text().splitlines()]
            cleanup=execute_report(db,cleanup_sql(rows),f'cleanup-{number:03}')
            json_write(folder/'staging-cleanup.json',cleanup)
        print(json.dumps({'chunk':number,'mode':'commit' if args.publish else 'rollback',
                          'publishable':report['publishable'],'inserted':report['inserted_snapshots']}),flush=True)
    summary={key:sum(r.get(key,0) for r in reports) for key in
             ('input_records','publishable','inserted_snapshots','new_staging_rows','reused_staging','skipped_snapshot_conflicts')}
    summary.update(chunks=len(reports),mode='commit' if args.publish else 'rollback',
                   finished_at=datetime.now(timezone.utc).isoformat())
    json_write(args.out_dir/('publication-report.json' if args.publish else 'dry-run-report.json'),summary)
    manifest['published' if args.publish else 'dry_run_passed']=True
    json_write(args.out_dir/'manifest.json',manifest)
    print(json.dumps(summary),flush=True)


if __name__=='__main__':main()
