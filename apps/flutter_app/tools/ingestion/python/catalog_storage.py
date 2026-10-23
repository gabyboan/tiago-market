"""Bounded storage maintenance. Preserve current observations and pending reviews.

Old snapshots are removed only after a private remote archive and its manifest
have been downloaded again and verified. No raw data belongs in public artifacts.
"""
import argparse
from datetime import datetime, timezone
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess
from uuid import uuid4

from refresh_online_catalog import Database, ROOT, literal

LIMIT_BYTES = 400 * 1024 * 1024
BUCKET = 'catalog-private-archives'

# Serialize publications across matrix workers, with 100 MiB of quota headroom.
# A DO block adds no result row, preserving the existing publication report.
CAPACITY_GUARD = f"""
do $$ begin
  perform pg_advisory_xact_lock(hashtextextended('tiago-catalog-capacity', 0));
  if pg_database_size(current_database()) >= {LIMIT_BYTES} then
    raise exception 'Catalog database capacity guard: run private archival maintenance before publishing';
  end if;
end $$;
"""

LATEST_SUCCESSOR = """exists (
  select 1 from public.price_snapshots newer
  where newer.store_product_id=p.store_product_id
    and newer.branch_id is not distinct from p.branch_id
    and newer.price_scope=p.price_scope
    and (newer.captured_at, newer.id) > (p.captured_at, p.id)
)"""


def old_snapshots_sql(cutoff):
    return f"""select to_jsonb(p) as row, md5(to_jsonb(p)::text) as fingerprint
from public.price_snapshots p
where p.captured_at < {literal(cutoff)}::timestamptz and {LATEST_SUCCESSOR}
order by p.id limit 500"""


def cleanup_sql(rows=None, cursor=None):
    restriction = ''
    if rows is not None:
        identities = json.dumps([{'source': r['source'], 'hash': r['content_hash']} for r in rows])
        restriction = f"""and (s.source,s.content_hash) in (
select source, hash from jsonb_to_recordset({literal(identities)}::jsonb) as x(source text, hash text))"""
    # Whole-payload equality deliberately keeps unusual historical mismatches.
    after = 'and s.id > ' + literal(cursor) + '::uuid' if cursor else ''
    return f"""with candidates as materialized (
select s.id, s.source, s.content_hash, s.payload from ingestion.source_price_staging s
where s.review_status='accepted' and s.content_hash is not null {restriction} {after}
order by s.id limit 400
), published as materialized (
select distinct c.id from candidates c
cross join lateral (select p.raw_payload from public.price_snapshots p
  where p.raw_payload ? 'content_hash'
    and p.source=c.source and p.raw_payload->>'content_hash'=c.content_hash offset 0) p
where p.raw_payload=c.payload
), removed as (
delete from ingestion.source_price_staging s using published p where s.id=p.id
returning s.id)
select jsonb_build_object('removed',count(*), 'cursor',(select max(id::text) from candidates),
       'scanned',(select count(*) from candidates)) as maintenance_report from removed"""


def execute_report(db, sql, label):
    # Data-changing CTEs must stay at the top level, outside Database.query's
    # read-only aggregation subquery. Return one JSON value on both transports.
    result = json.loads(db.execute(sql + ';', label))
    return result if db.url else result['rows'][0]['maintenance_report']


def cleanup_published(db):
    cursor = None
    removed = 0
    for _ in range(1000):
        result = execute_report(db, cleanup_sql(cursor=cursor), 'cleanup-published-staging')
        removed += result['removed']
        if not result['scanned']:
            return removed
        cursor = result['cursor']
    raise RuntimeError('Staging cleanup batch budget reached')


def delete_archived_sql(rows, cutoff):
    identities = json.dumps([{'id': r['row']['id'], 'fingerprint': r['fingerprint']} for r in rows])
    return f"""with archived as (
select * from jsonb_to_recordset({literal(identities)}::jsonb) as x(id uuid, fingerprint text)
), removed as (
delete from public.price_snapshots p using archived a
where p.id=a.id and md5(to_jsonb(p)::text)=a.fingerprint
  and p.captured_at < {literal(cutoff)}::timestamptz and {LATEST_SUCCESSOR}
returning p.id) select jsonb_build_object('removed',count(*)) as maintenance_report from removed"""


def upload_verified(path, object_name):
    helper = ROOT.parents[1] / 'scripts/private-storage-archive.mjs'
    result = subprocess.run(['node', str(helper), str(path), object_name],
                            capture_output=True, text=True, timeout=180)
    if result.returncode:
        raise RuntimeError('Private upload/verification failed; no corresponding rows were deleted')
    receipt = json.loads(result.stdout)
    if (receipt.get('verified') is not True or receipt.get('bucket') != BUCKET
            or receipt.get('object') != object_name
            or receipt.get('sha256') != hashlib.sha256(path.read_bytes()).hexdigest()):
        raise RuntimeError('Invalid archive receipt; no corresponding rows were deleted')
    return receipt


def archive_batch(db, folder, rows, cutoff):
    name = datetime.now(timezone.utc).strftime('%Y/%m/%d/') + str(uuid4())
    path = folder / (name.rsplit('/', 1)[-1] + '.ndjson.gz')
    data = ''.join(json.dumps(row, sort_keys=True, ensure_ascii=False) + '\n' for row in rows).encode()
    path.write_bytes(gzip.compress(data, mtime=0))
    # Validate local reconstruction before requesting a remote write.
    if [json.loads(line) for line in gzip.decompress(path.read_bytes()).splitlines()] != rows:
        raise RuntimeError('Local archive validation failed')
    receipt = upload_verified(path, 'price_snapshots/' + name + '.ndjson.gz')
    manifest = path.with_suffix('.manifest.json')
    manifest.write_text(json.dumps({'format': 1, 'table': 'public.price_snapshots',
                                   'cutoff': cutoff, 'rows': len(rows),
                                   'project_url': os.environ.get('SUPABASE_URL'), **receipt}) + '\n')
    upload_verified(manifest, 'price_snapshots/' + name + '.manifest.json')
    # Fingerprints and current/latest protection are checked again at deletion.
    return execute_report(db, delete_archived_sql(rows, cutoff), 'delete-archived')['removed']


def maintain(db, folder, *, apply=False):
    cutoff = db.query("select now()-interval '90 days' as cutoff", 'archive-cutoff')[0]['cutoff']
    report = {'retention_days': 90, 'archived': 0, 'staging_removed': 0, 'apply': apply}
    if not apply:
        report['eligible_first_batch'] = len(db.query(old_snapshots_sql(cutoff), 'archive-preview'))
        return report
    report['staging_removed'] = cleanup_published(db)
    for _ in range(100):
        rows = db.query(old_snapshots_sql(cutoff), 'archive-select')
        if not rows:
            break
        used = db.query("select coalesce(sum((metadata->>'size')::bigint),0) as bytes "
                        f"from storage.objects where bucket_id={literal(BUCKET)}", 'archive-quota')[0]['bytes']
        if used >= 700 * 1024 * 1024:
            raise RuntimeError('Private archive storage guard reached; preserve existing archives and review capacity')
        deleted = archive_batch(db, folder, rows, cutoff)
        report['archived'] += deleted
        print(json.dumps({'archived_batch': deleted, 'archived_total': report['archived']}), flush=True)
        if deleted != len(rows):
            raise RuntimeError('Snapshot changed during archival; verified archive retained for review')
    else:
        raise RuntimeError('Archive batch budget reached; rerun maintenance before refreshing')
    # Ordinary VACUUM releases dead space for reuse without locking the catalog.
    db.execute('vacuum (analyze) ingestion.source_price_staging;', 'vacuum-staging')
    db.execute('vacuum (analyze) public.price_snapshots;', 'vacuum-snapshots')
    report['database_bytes'] = db.query('select pg_database_size(current_database()) as bytes', 'capacity')[0]['bytes']
    if report['database_bytes'] >= LIMIT_BYTES:
        raise RuntimeError('Database capacity guard reached after maintenance; review storage before refreshing')
    return report


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work-dir', type=Path, required=True)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    if args.apply:
        if not os.environ.get('SUPABASE_SERVICE_ROLE_KEY'):
            raise RuntimeError('Private archive service credentials are required')
        if os.environ.get('SUPABASE_DB_URL'):
            from scheduled_source_refresh import validate_config
            validate_config(os.environ)
    args.work_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    report = maintain(Database(args.work_dir), args.work_dir, apply=args.apply)
    (args.work_dir / 'maintenance-report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))


if __name__ == '__main__':
    main()
