create view public.product_coverage
with (security_invoker = true)
as
select
  product_id,
  product_name,
  normalized_name,
  category,
  count(distinct store_id)::integer as store_count,
  count(distinct store_product_id)::integer as listing_count,
  array_agg(distinct source order by source) as sources,
  min(last_updated_at) as oldest_observation_at,
  max(last_updated_at) as last_updated_at
from public.latest_prices
group by product_id, product_name, normalized_name, category;

grant select on table public.product_coverage to service_role;
