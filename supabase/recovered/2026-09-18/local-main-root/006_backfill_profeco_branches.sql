update public.price_snapshots ps
set
  source_product_name = split_part(sp.external_name, ' · ', 1),
  source_branch_name = split_part(sp.external_name, ' · ', 2)
from public.store_products sp
where sp.id = ps.store_product_id
  and ps.source = 'profeco'
  and ps.source_branch_name is null
  and position(' · ' in sp.external_name) > 0;
