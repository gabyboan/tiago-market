"""Exercise archival deletion and staging safety in the isolated SQL CI DB."""
from pathlib import Path
import gzip
import hashlib
import json
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / 'apps/flutter_app/tools/ingestion/python'))
from catalog_storage import cleanup_sql, old_snapshots_sql, delete_archived_sql  # noqa: E402
from restore_catalog_archive import restore_sql  # noqa: E402


def main():
    cutoff = '2026-07-01T00:00:00Z'
    sql = """
begin;
do $$ begin
if current_database() <> 'tiago_catalog_test' then raise exception 'Isolated fixture DB required'; end if;
end $$;
create schema ingestion;
create table public.price_snapshots(
id uuid primary key, store_product_id uuid, branch_id uuid, price_scope text,
captured_at timestamptz, source text, raw_payload jsonb);
create table ingestion.source_price_staging(
id int primary key, source text, content_hash text, review_status text, payload jsonb);
insert into public.price_snapshots values
('00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',null,'online','2026-01-01','test','{"content_hash":"one","price":10}'),
('00000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002',null,'online','2026-01-01','test','{"content_hash":"two","price":20}'),
('00000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000002',null,'online','2026-08-01','test','{"content_hash":"three","price":30}'),
('00000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000001','branch_local','2026-01-01','test','{}'),
('00000000-0000-0000-0000-000000000005','10000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000002','branch_local','2026-08-01','test','{}'),
('00000000-0000-0000-0000-000000000006','10000000-0000-0000-0000-000000000004',null,'online','2026-01-01','test','{}'),
('00000000-0000-0000-0000-000000000007','10000000-0000-0000-0000-000000000004',null,'branch_local','2026-08-01','test','{}'),
('00000000-0000-0000-0000-000000000008','10000000-0000-0000-0000-000000000005',null,'online','2026-01-01','test','{}'),
('00000000-0000-0000-0000-000000000009','10000000-0000-0000-0000-000000000005',null,'online','2026-01-01','test','{}');
insert into ingestion.source_price_staging values
(1,'test','one','accepted','{"content_hash":"one","price":10}'),
(2,'test','one','accepted','{"content_hash":"one","price":999}'),
(3,'test','one','pending','{"content_hash":"one","price":10}'),
(4,'test','unpublished','accepted','{"content_hash":"unpublished"}');
"""
    sql += cleanup_sql() + ';\n'
    sql += """do $$ begin
if (select array_agg(id order by id) from ingestion.source_price_staging) <> array[2,3,4]
then raise exception 'Cleanup removed pending, mismatched or unpublished evidence'; end if;
end $$;
"""
    sql += 'create temporary table eligible as ' + old_snapshots_sql(cutoff) + ';\n'
    sql += """do $$ begin
if (select count(*) from eligible) <> 2 then raise exception 'Latest/branch/scope archival protection failed'; end if;
end $$;
"""
    # A stale archive fingerprint must not authorize deleting a changed row.
    sql += delete_archived_sql([{'row': {'id': '00000000-0000-0000-0000-000000000002'},
                                 'fingerprint': 'stale'}], cutoff) + ';\n'
    sql += "do $$ begin if (select count(*) from public.price_snapshots) <> 9 then raise exception 'Stale fingerprint deleted a row'; end if; end $$;\n"
    # Use fingerprints actually selected by PostgreSQL for the successful path.
    template = delete_archived_sql([], cutoff).replace("'[]'::jsonb", "(select jsonb_agg(jsonb_build_object('id',row->>'id','fingerprint',fingerprint)) from eligible)")
    sql += template + ';\n'
    sql += """do $$ begin
if (select count(*) from public.price_snapshots) <> 7 then raise exception 'Archive removal count failed'; end if;
if exists(select 1 from public.price_snapshots where id in ('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000008'))
then raise exception 'Archived observations were not removed'; end if;
end $$;
"""
    with tempfile.TemporaryDirectory() as folder:
        archive = Path(folder) / 'snapshot.ndjson.gz'
        manifest = Path(folder) / 'snapshot.manifest.json'
        archive.write_bytes(gzip.compress((json.dumps({'row': {
            'id': '00000000-0000-0000-0000-000000000002',
            'store_product_id': '10000000-0000-0000-0000-000000000002',
            'branch_id': None, 'price_scope': 'online', 'captured_at': '2026-01-01T00:00:00Z',
            'source': 'test', 'raw_payload': {'content_hash': 'two', 'price': 20}},
            'fingerprint': 'fixture'}) + '\n').encode()))
        manifest.write_text(json.dumps({'format': 1, 'table': 'public.price_snapshots',
                                       'rows': 1, 'sha256': hashlib.sha256(archive.read_bytes()).hexdigest()}))
        restored = restore_sql(archive, manifest, apply=True).removeprefix('begin;').removesuffix('commit;')
        sql += restored + restored
    sql += "do $$ begin if (select count(*) from public.price_snapshots) <> 8 then raise exception 'Archive restore/replay failed'; end if; end $$;\n"
    sql += """
do $$ begin
if not exists(select 1 from pg_roles where rolname='anon') then create role anon; end if;
if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if;
end $$;
create view public.latest_prices as select id from public.price_snapshots;
grant select on public.latest_prices to anon, authenticated;
create function public.legacy_fixture_count() returns bigint language sql security definer
set search_path=public as $$ select count(*) from public.latest_prices $$;
"""
    sql += (root / 'apps/flutter_app/supabase/migrations/20261022220843_harden_legacy_latest_prices_view.sql').read_text()
    sql += """do $$ begin
if has_table_privilege('anon','public.latest_prices','SELECT') or has_table_privilege('authenticated','public.latest_prices','SELECT')
then raise exception 'Legacy view still exposed directly'; end if;
end $$;
set local role anon;
select public.legacy_fixture_count() as legacy_rpc_still_available;
reset role;
rollback;
"""
    subprocess.run(['psql', '-X', '--set', 'ON_ERROR_STOP=1'], input=sql, text=True, check=True)


if __name__ == '__main__':
    main()
