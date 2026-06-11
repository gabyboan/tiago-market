alter table public.price_snapshots
  add column source text,
  add column captured_at timestamptz,
  add column source_product_name text,
  add column source_store_name text,
  add column source_branch_name text,
  add column source_city_code text,
  add column source_city_name text,
  add column external_reference text,
  add column raw_payload jsonb;

update public.price_snapshots ps
set
  source = sp.source,
  captured_at = ps.scraped_at,
  source_product_name = sp.external_name,
  source_store_name = s.name,
  external_reference = sp.external_url,
  raw_payload = jsonb_build_object(
    'backfilled', true,
    'store_product_id', sp.id,
    'scraped_at', ps.scraped_at
  )
from public.store_products sp
join public.stores s on s.id = sp.store_id
where sp.id = ps.store_product_id;

alter table public.price_snapshots
  alter column source set not null,
  alter column captured_at set not null,
  alter column source_product_name set not null,
  alter column source_store_name set not null,
  alter column raw_payload set not null,
  alter column raw_payload set default '{}'::jsonb;

create index price_snapshots_source_captured_at_idx
  on public.price_snapshots (source, captured_at desc);

create index price_snapshots_city_code_idx
  on public.price_snapshots (source_city_code)
  where source_city_code is not null;

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
  ps.source_branch_name as branch_name,
  ps.source_product_name,
  ps.external_reference,
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
    external_reference
  from public.price_snapshots
  where store_product_id = sp.id
  order by captured_at desc, id desc
  limit 1
) ps on true
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
  count(distinct store_product_id)::integer as listing_count,
  array_agg(distinct source order by source) as sources,
  min(captured_at) as oldest_observation_at,
  max(captured_at) as last_updated_at
from public.latest_prices
group by product_id, product_name, normalized_name, category;

create view public.source_stats
with (security_invoker = true)
as
select
  source,
  count(*)::integer as total_snapshots,
  count(distinct store_product_id)::integer as total_listings,
  count(distinct source_store_name)::integer as total_stores,
  count(distinct source_branch_name)::integer as total_branches,
  min(captured_at) as oldest_snapshot_at,
  max(captured_at) as latest_snapshot_at
from public.price_snapshots
group by source;

create view public.coverage_summary
with (security_invoker = true)
as
with
snapshot_totals as (
  select
    count(*)::integer as total_price_snapshots,
    count(distinct source_branch_name)::integer as total_branches,
    min(captured_at) as oldest_snapshot_at,
    max(captured_at) as latest_snapshot_at
  from public.price_snapshots
),
snapshot_sources as (
  select jsonb_object_agg(source, total order by source) as values
  from (
    select source, count(*)::integer as total
    from public.price_snapshots
    group by source
  ) grouped
),
product_sources as (
  select jsonb_object_agg(source, total order by source) as values
  from (
    select source, count(distinct product_id)::integer as total
    from public.store_products
    group by source
  ) grouped
),
store_sources as (
  select jsonb_object_agg(source, total order by source) as values
  from (
    select source, count(distinct store_id)::integer as total
    from public.store_products
    group by source
  ) grouped
)
select
  (select count(*)::integer from public.products) as total_products,
  (select count(*)::integer from public.stores where enabled = true) as total_stores,
  snapshot_totals.total_branches,
  snapshot_totals.total_price_snapshots,
  snapshot_totals.latest_snapshot_at,
  snapshot_totals.oldest_snapshot_at,
  coalesce(snapshot_sources.values, '{}'::jsonb) as snapshots_by_source,
  coalesce(product_sources.values, '{}'::jsonb) as products_by_source,
  coalesce(store_sources.values, '{}'::jsonb) as stores_by_source
from snapshot_totals
cross join snapshot_sources
cross join product_sources
cross join store_sources;

grant select on table
  public.latest_prices,
  public.compare_prices,
  public.product_coverage,
  public.source_stats,
  public.coverage_summary
to service_role;

comment on column public.price_snapshots.captured_at is
  'Fecha de observación informada por la fuente; no implica precio en tiempo real.';

comment on column public.price_snapshots.raw_payload is
  'Payload original conservado para auditoría y diagnóstico.';
