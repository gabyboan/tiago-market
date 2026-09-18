alter table public.store_products
  add column store_product_url text;

drop view public.product_coverage;
drop view public.compare_prices;
drop view public.latest_prices;

create view public.latest_prices
with (security_invoker = true)
as
select
  sp.id as store_product_id,
  p.id as product_id,
  p.name as product_name,
  p.normalized_name,
  p.category,
  s.id as store_id,
  ps.source_store_name as store_name,
  s.slug as store_slug,
  b.id as branch_id,
  ps.source_branch_name as branch_name,
  b.address as branch_address,
  b.neighborhood as branch_neighborhood,
  b.postal_code as branch_postal_code,
  b.municipality as branch_municipality,
  b.state as branch_state,
  b.latitude,
  b.longitude,
  ps.source_product_name,
  ps.external_reference as observation_url,
  sp.store_product_url,
  sp.image_url,
  sp.presentation,
  ps.price,
  ps.currency,
  ps.available,
  ps.source,
  ps.captured_at,
  greatest(0, current_date - ps.captured_at::date)::integer as days_old,
  case
    when current_date - ps.captured_at::date < 7 then 'fresh'
    when current_date - ps.captured_at::date <= 21 then 'stale'
    else 'old'
  end as freshness
from public.store_products sp
join public.stores s on s.id = sp.store_id
join public.products p on p.id = sp.product_id
join lateral (
  select
    price,
    currency,
    available,
    source,
    captured_at,
    source_product_name,
    source_store_name,
    source_branch_name,
    external_reference,
    branch_id
  from public.price_snapshots
  where store_product_id = sp.id
  order by captured_at desc, id desc
  limit 1
) ps on true
left join public.branches b on b.id = ps.branch_id
where s.enabled = true;

create view public.compare_prices
with (security_invoker = true)
as
select
  latest_prices.*,
  dense_rank() over (
    partition by normalized_name
    order by price asc
  ) as price_rank,
  min(price) over (
    partition by normalized_name
  ) as best_price
from public.latest_prices
where available = true;

create view public.product_coverage
with (security_invoker = true)
as
select
  product_id,
  product_name,
  normalized_name,
  category,
  count(distinct store_id)::integer as store_count,
  count(distinct branch_id)::integer as listing_count,
  array_agg(distinct source order by source) as sources,
  min(captured_at) as oldest_observation_at,
  max(captured_at) as last_updated_at
from public.latest_prices
group by product_id, product_name, normalized_name, category;

grant select on table
  public.latest_prices,
  public.compare_prices,
  public.product_coverage
to service_role;

grant update (store_product_url) on table public.store_products to service_role;

comment on column public.store_products.store_product_url is
  'URL verificable de la ficha oficial de la tienda; null cuando la fuente no la proporciona.';
