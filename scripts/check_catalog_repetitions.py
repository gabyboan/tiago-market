"""Verify that archival retains price changes, validity and current observations."""
from pathlib import Path
import json
import subprocess
import sys
from uuid import UUID

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / 'apps/flutter_app/tools/ingestion/python'))
from catalog_storage import repeated_snapshot_ids_sql, delete_archived_sql  # noqa: E402
from refresh_online_catalog import literal  # noqa: E402


def main():
    rows, removable = [], []

    def add(group, prices, internal, *, availability=None, currencies=None,
            evidence=None, branches=None, scopes=None, sources=None, names=None, tied=False):
        for offset, price in enumerate(prices):
            identity = str(UUID(int=group * 100 + offset + 1))
            rows.append({'id': identity, 'store_product_id': str(UUID(int=group)),
                         'branch_id': str(UUID(int=branches[offset])) if branches else None,
                         'price_scope': scopes[offset] if scopes else 'online',
                         'captured_at': f'2026-06-{1 if tied else offset + 1:02}T12:00:00Z',
                         'source': sources[offset] if sources else 'test', 'price': price,
                         'available': availability[offset] if availability else True,
                         'currency': currencies[offset] if currencies else 'MXN',
                         'source_product_name': names[offset] if names else 'Leche',
                         'raw_payload': evidence[offset] if evidence else {}})
            if offset in internal:
                removable.append(identity)

    add(1, [10, 10, 10, 10, 10], [1, 2, 3])
    add(2, [10, 10, 20, 20, 20, 10, 10], [3])  # return to a former price
    add(3, [10] * 6, [3], availability=[True, True, False, False, False, True])
    add(4, [10] * 5, [3], currencies=['MXN', 'MXN', 'USD', 'USD', 'USD'])
    add(5, [10] * 6, [1, 4], evidence=[{'valid_until': '2026-12-01'}] * 3 + [{'valid_until': '2026-12-02'}] * 3)
    add(6, [10] * 6, [1, 4], evidence=[{'review_status': 'accepted'}] * 3 + [{'review_status': 'rejected'}] * 3)
    add(7, [10] * 6, [1, 4], evidence=[{'is_synthetic': False}] * 3 + [{'is_synthetic': True}] * 3)
    add(8, [10] * 6, [1, 4], sources=['first'] * 3 + ['second'] * 3)
    add(9, [10] * 6, [1, 4], names=['Leche entera'] * 3 + ['Leche descremada'] * 3)
    add(10, [10] * 4, [], branches=[1, 2, 1, 2])
    add(11, [10] * 4, [], scopes=['online', 'branch_local', 'online', 'branch_local'])
    add(12, [10], [])
    add(13, [10, 10, 10], [1], tied=True)
    add(14, [10, 10], [])

    sql = """begin;
do $$ begin
if current_database() <> 'tiago_catalog_test' then raise exception 'Isolated fixture DB required'; end if;
end $$;
create table public.price_snapshots(
id uuid primary key, store_product_id uuid,branch_id uuid,price_scope text,
captured_at timestamptz,source text,price numeric,currency text,available boolean,
source_product_name text,source_store_name text,source_branch_name text,
source_city_code text,source_city_name text,external_reference text,raw_payload jsonb);
create index on public.price_snapshots(store_product_id,captured_at,id);
"""
    sql += 'insert into public.price_snapshots select * from jsonb_populate_recordset(null::public.price_snapshots,' + literal(json.dumps(rows)) + '::jsonb);\n'
    sql += """create temporary table latest_before as
select distinct on (store_product_id,branch_id,price_scope) id from public.price_snapshots
order by store_product_id,branch_id,price_scope,captured_at desc,id desc;
"""
    sql += 'create temporary table repeated as ' + repeated_snapshot_ids_sql() + ';\n'
    expected = 'array[' + ','.join(literal(value) for value in sorted(removable)) + ']::text[]'
    sql += f"do $$ begin if (select array_agg(id::text order by id) from repeated) <> {expected} then raise exception 'Unexpected repetition candidate set'; end if; end $$;\n"
    sql += "create temporary table archived as select to_jsonb(p) as row,md5(to_jsonb(p)::text) as fingerprint from public.price_snapshots p join repeated r using(id);\n"
    deletion = delete_archived_sql([], None, reason='repeated').replace("'[]'::jsonb", "(select jsonb_agg(jsonb_build_object('id',row->>'id','fingerprint',fingerprint)) from archived)")
    sql += deletion + ';\n'
    sql += f"do $$ begin if (select count(*) from public.price_snapshots) <> {len(rows) - len(removable)} then raise exception 'Repetition removal count failed'; end if; end $$;\n"
    sql += 'create temporary table remaining_candidates as ' + repeated_snapshot_ids_sql() + ';\n'
    sql += """do $$ begin
if exists(select 1 from remaining_candidates) then raise exception 'Compaction is not idempotent'; end if;
if exists(select id from latest_before except select id from public.price_snapshots)
then raise exception 'A current observation was lost'; end if;
end $$;
"""
    # A candidate's payload can remain unchanged while a neighbor becomes a
    # different price. Recheck both neighbors before deleting its archived copy.
    sql += """insert into public.price_snapshots(id,store_product_id,price_scope,captured_at,source,price,currency,available,raw_payload)
values ('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','online','2026-06-01','test',10,'MXN',true,'{}'),
('10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000001','online','2026-06-02','test',10,'MXN',true,'{}'),
('10000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000001','online','2026-06-03','test',10,'MXN',true,'{}');
truncate archived;
insert into archived select to_jsonb(p),md5(to_jsonb(p)::text) from public.price_snapshots p where id='10000000-0000-0000-0000-000000000002';
update public.price_snapshots set price=20 where id='10000000-0000-0000-0000-000000000001';
"""
    sql += deletion + ';\n'
    sql += "do $$ begin if not exists(select 1 from public.price_snapshots where id='10000000-0000-0000-0000-000000000002') then raise exception 'Changed neighbor was ignored'; end if; end $$;\n"
    sql += "update public.price_snapshots set price=10 where id='10000000-0000-0000-0000-000000000001'; update public.price_snapshots set price=15 where id='10000000-0000-0000-0000-000000000002';\n"
    sql += deletion + ';\n'
    sql += "do $$ begin if not exists(select 1 from public.price_snapshots where id='10000000-0000-0000-0000-000000000002') then raise exception 'Changed archived payload was deleted'; end if; end $$; rollback;\n"
    subprocess.run(['psql', '-X', '--set', 'ON_ERROR_STOP=1'], input=sql, text=True, check=True)


if __name__ == '__main__':
    main()
