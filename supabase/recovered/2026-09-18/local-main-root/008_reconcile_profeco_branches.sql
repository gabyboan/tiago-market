create temporary table branch_merge_map on commit drop as
select
  legacy.id as legacy_id,
  current.id as current_id
from public.branches legacy
join public.branches current
  on current.source = legacy.source
  and current.store_id = legacy.store_id
  and lower(current.name) = lower(legacy.name)
  and current.city_code is not null
where legacy.source = 'profeco'
  and legacy.city_code is null;

update public.store_products sp
set branch_id = mapping.current_id
from branch_merge_map mapping
where sp.branch_id = mapping.legacy_id;

update public.price_snapshots ps
set branch_id = mapping.current_id
from branch_merge_map mapping
where ps.branch_id = mapping.legacy_id;

delete from public.branches b
using branch_merge_map mapping
where b.id = mapping.legacy_id;

update public.branches b
set
  city_code = '0901',
  external_key = md5(concat_ws(
    '|',
    b.source,
    '0901',
    lower(s.name),
    lower(b.name)
  )),
  updated_at = now()
from public.stores s
where s.id = b.store_id
  and b.source = 'profeco'
  and b.city_code is null;
