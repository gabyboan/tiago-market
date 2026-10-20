#!/usr/bin/env python3
"""Refresh only already-published Chedraui/Merco URLs through existing staging."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from urllib.parse import urlparse

from daily_basket_update import read_json, read_ndjson, run_logged
from merco_online_scraper import product_url
from online_catalog import timestamp
from verify_catalog_rpc import verify

ROOT = Path(__file__).resolve().parents[3]
SOURCES = ('chedraui-mx', 'merco-mx')


def now():
    return datetime.now(timezone.utc).isoformat()


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def write_rows(path, rows):
    path.write_text(''.join(json.dumps(r, ensure_ascii=False) + '\n' for r in rows))


def literal(value):
    return "'" + str(value).replace("'", "''") + "'"


class Database:
    """Use the existing DB URL, or the already authenticated linked Supabase CLI."""
    def __init__(self, folder):
        self.folder = folder
        self.counter = 0
        self.url = os.environ.get('SUPABASE_DB_URL', '').strip()
        binary = 'psql' if self.url else 'supabase'
        if not shutil.which(binary):
            raise RuntimeError(f'Required executable unavailable: {binary}')

    def execute(self, sql, label):
        self.counter += 1
        path = self.folder / f'db-{self.counter:02}-{label}.sql'
        path.write_text(sql)
        env = os.environ.copy()
        if self.url:
            # Avoid placing connection credentials in process arguments or logs.
            env['PGDATABASE'] = self.url
            env['PGCONNECT_TIMEOUT'] = '20'
            command = ['psql', '-X', '-qAt', '--set', 'ON_ERROR_STOP=1', '--file', str(path)]
        else:
            command = ['supabase', 'db', 'query', '--linked', '--output', 'json', '--file', str(path)]
        result = subprocess.run(command, cwd=ROOT, env=env, text=True,
                                capture_output=True, timeout=120)
        # CLI errors can contain a connection URI; keep credentials out of reports.
        output = result.stdout + '\n' + result.stderr
        if self.url:
            output = output.replace(self.url, '[REDACTED_DB_URL]')
        output = re.sub(r'postgres(?:ql)?://[^\s]+', '[REDACTED_DB_URL]', output)
        path.with_suffix('.log').write_text(output)
        if result.returncode:
            raise RuntimeError(f'Database {label} failed; see {path.with_suffix(".log").name}')
        return result.stdout

    def query(self, sql, label):
        wrapped = f"select coalesce(jsonb_agg(q), '[]'::jsonb) as result from ({sql.rstrip(';')}) q;"
        output = self.execute(wrapped, label)
        if self.url:
            return json.loads(output.strip())
        document = json.loads(output)
        return document['rows'][0]['result']


KNOWN_SQL = """
select sp.source, sp.store_product_url, sp.external_name, sp.presentation,
       p.normalized_name, p.category, s.slug as store_slug,
       (select max(ps.captured_at) from public.price_snapshots ps
        where ps.store_product_id=sp.id and ps.price_scope='online') as latest_capture
from public.store_products sp
join public.products p on p.id=sp.product_id
join public.stores s on s.id=sp.store_id
where sp.source in ('chedraui-mx','merco-mx') and sp.branch_id is null
  and exists (select 1 from public.price_snapshots ps where ps.store_product_id=sp.id
              and ps.price_scope='online' and ps.branch_id is null)
order by sp.source,sp.store_product_url
"""


def known_by_source(listings):
    groups = {source: {} for source in SOURCES}
    for listing in listings:
        source, url = listing['source'], listing['store_product_url']
        parsed = urlparse(url or '')
        valid = product_url(url) if source == 'merco-mx' else (
            parsed.scheme == 'https' and parsed.netloc == 'www.chedraui.com.mx'
            and not parsed.query and not parsed.fragment
            and re.fullmatch(r'/[a-zA-Z0-9%-]+-\d+/p', parsed.path))
        if not valid:
            raise ValueError(f'Invalid persisted URL for {source}: {url}')
        if url in groups[source]:
            raise ValueError(f'Duplicate persisted listing: {source} {url}')
        groups[source][url] = listing
    return groups


def prepare_rows(rows, source, known):
    """Do not add listings or silently change an existing product identity."""
    accepted, rejected = [], []
    for row in rows:
        url = row.get('store_product_url')
        listing = known.get(url)
        reason = None
        if row.get('source') != source or listing is None:
            reason = 'unknown_listing'
        elif row.get('source_url') != url:
            reason = 'changed_evidence_url'
        elif (row.get('normalized_name') != listing['normalized_name'] or
              row.get('source_product_name') != listing['external_name']):
            reason = 'changed_product_identity'
        elif row.get('presentation') != listing['presentation']:
            reason = 'changed_presentation'
        elif row.get('store_slug') != listing['store_slug']:
            reason = 'changed_store'
        elif listing.get('latest_capture'):
            try:
                if not isinstance(row.get('captured_at'), str):
                    raise ValueError('Missing captured_at')
                if timestamp(row['captured_at']) < timestamp(listing['latest_capture']):
                    reason = 'older_than_current_observation'
            except (ValueError, KeyError, TypeError):
                reason = 'invalid_captured_at'
        if reason:
            rejected.append({'url': url, 'reason': reason})
        else:
            # Keep existing reviewed categories; refresh only the observation.
            accepted.append(dict(row, category=listing['category']))
    return accepted, rejected


def capture_source(source, known, folder, delay_ms):
    out = folder / f'{source}.ndjson'
    urls = folder / f'{source}-urls.json'
    write_json(urls, list(known))
    if not known:
        write_rows(out, [])
        return {'exit_code': 0, 'attempted': 0, 'accepted': 0, 'rejected': [], 'failure': None}
    if source == 'chedraui-mx':
        evidence = folder / 'chedraui-evidence'
        command = ['dart', 'run', 'tools/ingestion/bin/chedraui_sitemap_scraper.dart',
                   '--urls', str(urls), '--limit', str(len(known)), '--out', str(out),
                   '--delay-ms', str(delay_ms), '--evidence-dir', str(evidence)]
    else:
        evidence = Path(str(out) + '.evidence')
        command = [sys.executable, 'tools/ingestion/python/merco_online_scraper.py',
                   '--urls', str(urls), '--limit', str(len(known)), '--out', str(out),
                   '--delay-ms', str(delay_ms)]
    print(f'{source}: comprobando robots y capturando {len(known)} URLs conocidas...', flush=True)
    code = run_logged(command, folder / f'{source}-capture.log')
    details = read_json(evidence / 'report.json') or {}
    result = dict(details, exit_code=code)
    result['attempted'] = details.get('attempted', details.get('attempted_product_pages', 0))
    if code and not details.get('rejected') and not details.get('failure'):
        result['failure'] = f'Capture failed (exit {code}); see {source}-capture.log'
    write_json(folder / f'{source}-capture.json', result)
    print(f'{source}: {result["attempted"]} consultados; salida {code}.', flush=True)
    return result


def publication_metadata(db, run_source, label):
    runs = db.query('select metadata from ingestion.scrape_runs where source=' +
                    literal(run_source) + ' order by started_at desc limit 1', label)
    if not runs:
        raise RuntimeError('Missing committed ingestion run')
    return runs[0]['metadata']


def publish_source(source, known, capture_folder, folder, db, run_id):
    capture = read_json(capture_folder / f'{source}-capture.json') or {}
    result = {'known': len(known), 'consulted': capture.get('attempted', 0),
              'capture': capture, 'valid': 0, 'inserted_snapshots': 0,
              'duplicates_avoided': 0, 'replay_duplicates_avoided': 0,
              'rejections': list(capture.get('rejected') or []), 'errors': []}
    if capture.get('failure'):
        result['errors'].append(capture['failure'])
    elif capture.get('exit_code', 0) and not capture.get('rejected'):
        result['errors'].append('Capture exited with an error')
    committed_rows = []
    try:
        raw_path = capture_folder / f'{source}.ndjson'
        if not raw_path.exists() and known:
            raise RuntimeError('No captured NDJSON; see source capture report')
        rows = read_ndjson(raw_path)
        rows, binding_rejections = prepare_rows(rows, source, known)
        result['rejections'].extend(binding_rejections)
        if not rows:
            return result, []
        prepared = folder / f'{source}-prepared.ndjson'
        write_rows(prepared, rows)
        sql_path = folder / f'{source}-publish.sql'
        preflight_path = folder / f'{source}-preflight.json'
        run_source = f'online-refresh:{run_id}:{source}'
        code = run_logged(['dart', 'run', 'tools/ingestion/bin/stage_ndjson.dart',
                           '--input', str(prepared), '--run-source', run_source,
                           '--sql-out', str(sql_path), '--allow-partial',
                           '--json-report', str(preflight_path)],
                          folder / f'{source}-preflight.log')
        preflight = read_json(preflight_path) or {}
        result['rejections'].extend(preflight.get('rejected_records', []))
        result['valid'] = preflight.get('publishable', 0)
        result['duplicates_avoided'] = preflight.get('duplicate_input_records', 0)
        if code or not sql_path.exists():
            result['errors'].append('Staging validation failed; see preflight report')
            return result, []
        valid_rows = preflight['publishable_records']
        sql = sql_path.read_text()
        db.execute(sql, source + '-publish')
        committed_rows = valid_rows
        metadata = publication_metadata(db, run_source, source + '-publication')
        result['publication'] = metadata
        result['inserted_snapshots'] = metadata['inserted_snapshots']
        result['duplicates_avoided'] += (metadata.get('skipped_existing_snapshots', 0) +
                                         metadata.get('skipped_snapshot_conflicts', 0))
        # Prove replay in a rollback transaction, without scraping or lasting changes.
        if not sql.rstrip().endswith('commit;'):
            raise RuntimeError('Unexpected staging transaction')
        replay = sql.rstrip()[:-len('commit;')] + """
do $replay$
begin
 if (select inserted_snapshots from ingestion.scrape_runs
     where id=current_setting('tiago.ingestion_run_id')::uuid) <> 0 then
   raise exception 'Replay inserted duplicate observations';
 end if;
end;
$replay$;
rollback;
"""
        db.execute(replay, source + '-replay')
        result['replay_duplicates_avoided'] = len(valid_rows)
        result['replay_verified'] = True
        return result, valid_rows
    except Exception as error:
        result['errors'].append(str(error))
        return result, committed_rows


def database_summary(db):
    return db.query("""
select s.source,
 (select count(*) from public.store_products sp where sp.source=s.source) as listings,
 (select count(*) from public.current_catalog_prices c where c.source=s.source and c.branch_id is null) as current_online,
 (select count(*) from public.current_catalog_prices c where c.source=s.source and c.available) as available,
 (select count(*) from public.current_catalog_prices c where c.source=s.source and not c.available) as out_of_stock,
 (select count(*) from public.price_snapshots ps where ps.source=s.source) as total_snapshots,
 (select max(captured_at) from public.price_snapshots ps where ps.source=s.source) as latest_capture,
 (select count(*) from (select store_product_url from public.store_products sp where sp.source=s.source
    group by store_product_url having count(*)>1) d) as duplicate_listings,
 (select count(*) from (select store_product_id,branch_id,captured_at from public.price_snapshots ps
    where ps.source=s.source group by store_product_id,branch_id,captured_at having count(*)>1) d) as duplicate_observations,
 (select count(*) from public.price_snapshots ps where ps.source=s.source
    and (ps.price_scope<>'online' or ps.branch_id is not null)) as local_observations
from (values ('chedraui-mx'),('merco-mx')) s(source)
""", 'verification')


def render_summary(report):
    lines = ['Tiago Market — actualización catálogo online', '']
    for source, result in report.get('sources', {}).items():
        lines.extend([source,
            f"  consultados: {result['consulted']} / {result['known']}",
            f"  válidos: {result['valid']}",
            f"  snapshots nuevos: {result['inserted_snapshots']}",
            f"  duplicados evitados: {result['duplicates_avoided']}",
            f"  duplicados evitados en replay: {result['replay_duplicates_avoided']}",
            f"  rechazados: {len(result['rejections'])}"])
        lines.extend('  error: ' + error for error in result['errors'])
    for result in report.get('database', []):
        lines.append(f"Supabase {result['source']}: {result['current_online']} actuales; "
                     f"{result['available']} disponibles; {result['out_of_stock']} sin stock; "
                     f"captura {result['latest_capture']}")
    lines.extend('Error: ' + error for error in report.get('errors', []))
    lines.extend([f"RPC online_prices_v4: {report.get('rpc_status', 'NO VERIFICADA')}",
                  f"Resultado: {report['status']}", f"Informe: {report['report_path']}"])
    return '\n'.join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work-dir', type=Path, help='New directory for immutable evidence and reports')
    parser.add_argument('--reuse', type=Path, help='Reprocess an existing capture directory without store HTTP requests')
    parser.add_argument('--defines', type=Path, default=ROOT / 'dart_defines.local.json')
    parser.add_argument('--delay-ms', type=int, default=5000)
    args = parser.parse_args(argv)
    if args.delay_ms < 5000:
        parser.error('--delay-ms must be at least 5000')
    run_id = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder = (args.work_dir or ROOT / 'build' / 'online-refresh' / run_id).resolve()
    if folder.exists():
        parser.error('--work-dir must not exist; use --reuse for captured evidence')
    folder.mkdir(parents=True)
    os.chdir(ROOT)
    report = {'started_at': now(), 'status': 'ERROR', 'sources': {}, 'errors': [],
              'report_path': str(folder / 'report.json')}
    try:
        for executable in ('dart', sys.executable):
            if not shutil.which(executable):
                raise RuntimeError(f'Required executable unavailable: {executable}')
        config = json.loads(args.defines.resolve().read_text())
        if not (config.get('SUPABASE_PUBLISHABLE_KEY') or config.get('SUPABASE_ANON_KEY')):
            raise RuntimeError('Missing public RPC key in defines configuration')
        db = Database(folder)
        if not db.url:
            project = (ROOT / 'supabase/.temp/project-ref').read_text().strip()
            if urlparse(config['SUPABASE_URL']).hostname != project + '.supabase.co':
                raise RuntimeError('Linked DB and public RPC configuration target different projects')
        listings = db.query(KNOWN_SQL, 'known-listings')
        known, preflight_errors = {}, {}
        for source in SOURCES:
            try:
                known[source] = known_by_source([r for r in listings if r['source'] == source])[source]
            except (ValueError, TypeError) as error:
                known[source] = {}
                preflight_errors[source] = str(error)
        write_json(folder / 'known-listings.json', listings)
        report['before'] = database_summary(db)
        capture_folder = args.reuse.resolve() if args.reuse else folder
        if args.reuse:
            if not capture_folder.is_dir():
                raise RuntimeError('--reuse capture directory does not exist')
        else:
            # Different origins; each existing connector stays sequential and paced.
            with ThreadPoolExecutor(max_workers=2) as pool:
                jobs = {source: pool.submit(capture_source, source, known[source], folder, args.delay_ms)
                        for source in SOURCES if source not in preflight_errors}
                for source, job in jobs.items():
                    try:
                        job.result()
                    except Exception as error:
                        write_json(folder / f'{source}-capture.json',
                                   {'attempted': 0, 'exit_code': 1, 'failure': str(error)})
        expected = []
        for source in SOURCES:
            if source in preflight_errors:
                report['sources'][source] = {
                    'known': sum(r['source'] == source for r in listings), 'consulted': 0,
                    'valid': 0, 'inserted_snapshots': 0, 'duplicates_avoided': 0,
                    'replay_duplicates_avoided': 0, 'rejections': [],
                    'errors': [preflight_errors[source]]}
                continue
            result, valid_rows = publish_source(source, known[source], capture_folder, folder, db, run_id)
            report['sources'][source] = result
            expected.extend(valid_rows)
            write_json(folder / 'report.json', report)
        write_rows(folder / 'published.ndjson', expected)
        report['database'] = database_summary(db)
        for item in report['database']:
            if item['duplicate_listings'] or item['duplicate_observations'] or item['local_observations']:
                report['errors'].append('Database integrity check failed: ' + item['source'])
        rpc = verify(config, expected)
        write_json(folder / 'rpc-verification.json', rpc)
        report['rpc_status'] = 'OK' if rpc['passed'] else 'ERROR'
        if not rpc['passed']:
            report['errors'].extend(rpc['errors'])
        partial = any(r['errors'] or r['rejections'] or r['consulted'] < r['known']
                      for r in report['sources'].values())
        report['status'] = 'ERROR' if report['errors'] else ('PARCIAL' if partial else 'OK')
    except Exception as error:
        report['errors'].append(str(error))
    finally:
        report['finished_at'] = now()
        write_json(folder / 'report.json', report)
        summary = render_summary(report)
        (folder / 'summary.txt').write_text(summary + '\n')
        print(summary, flush=True)
    return 0 if report['status'] == 'OK' else 2


if __name__ == '__main__':
    raise SystemExit(main())
