update ingestion.source_catalog
set
  status = 'candidate',
  notes = concat_ws(
    ' ',
    notes,
    'Reservado hasta tener captura por sucursal con branch_id/coordenadas; no usar en la experiencia principal geolocalizada.'
  ),
  updated_at = now()
where source_slug in ('chedraui-mx', 'steren-mx')
  and status = 'active'
  and capture_scope = 'online'
  and geolocatable = false;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'price_snapshots_branch_required_check'
      and conrelid = 'public.price_snapshots'::regclass
  ) then
    alter table public.price_snapshots
      add constraint price_snapshots_branch_required_check
      check (branch_id is not null) not valid;
  end if;
end $$;

alter table ingestion.source_price_staging
  drop constraint if exists source_price_staging_accepted_real_evidence_check;

alter table ingestion.source_price_staging
  add constraint source_price_staging_accepted_real_evidence_check
  check (
    review_status <> 'accepted'
    or (
      is_synthetic = false
      and evidence_kind <> 'unknown'
      and observed_at is not null
      and source_url is not null
      and source_url ~* '^https?://'
      and confidence_score >= 0.70
      and coalesce(cardinality(validation_errors), 0) = 0
      and nullif(normalized_payload->>'branch_external_key', '') is not null
      and nullif(normalized_payload->>'branch_name', '') is not null
      and nullif(normalized_payload->>'branch_address', '') is not null
      and nullif(normalized_payload->>'branch_municipality', '') is not null
      and nullif(normalized_payload->>'branch_state', '') is not null
      and (normalized_payload->>'latitude') ~ '^-?[0-9]+(\.[0-9]+)?$'
      and (normalized_payload->>'longitude') ~ '^-?[0-9]+(\.[0-9]+)?$'
      and (normalized_payload->>'latitude')::numeric between 14 and 33.5
      and (normalized_payload->>'longitude')::numeric between -119 and -86
    )
  ) not valid;

create or replace view ingestion.publishable_source_prices as
select *
from ingestion.source_price_staging
where review_status = 'accepted'
  and is_synthetic = false
  and evidence_kind <> 'unknown'
  and observed_at is not null
  and source_url is not null
  and source_url ~* '^https?://'
  and confidence_score >= 0.70
  and coalesce(cardinality(validation_errors), 0) = 0
  and nullif(normalized_payload->>'branch_external_key', '') is not null
  and nullif(normalized_payload->>'branch_name', '') is not null
  and nullif(normalized_payload->>'branch_address', '') is not null
  and nullif(normalized_payload->>'branch_municipality', '') is not null
  and nullif(normalized_payload->>'branch_state', '') is not null
  and (normalized_payload->>'latitude') ~ '^-?[0-9]+(\.[0-9]+)?$'
  and (normalized_payload->>'longitude') ~ '^-?[0-9]+(\.[0-9]+)?$'
  and (normalized_payload->>'latitude')::numeric between 14 and 33.5
  and (normalized_payload->>'longitude')::numeric between -119 and -86;

revoke all on ingestion.publishable_source_prices from anon, authenticated;
grant all on ingestion.publishable_source_prices to service_role;

create or replace view public.latest_prices as
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
  coalesce(ps.source_branch_name, b.name) as branch_name,
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
  greatest(0, current_date - ps.captured_at::date) as days_old,
  case
    when current_date - ps.captured_at::date < 7 then 'fresh'::text
    when current_date - ps.captured_at::date <= 21 then 'stale'::text
    else 'old'::text
  end as freshness
from public.store_products sp
join public.stores s on s.id = sp.store_id
join public.products p on p.id = sp.product_id
join lateral (
  select
    price_snapshots.price,
    price_snapshots.currency,
    price_snapshots.available,
    price_snapshots.source,
    price_snapshots.captured_at,
    price_snapshots.source_product_name,
    price_snapshots.source_store_name,
    price_snapshots.source_branch_name,
    price_snapshots.external_reference,
    price_snapshots.branch_id
  from public.price_snapshots
  where price_snapshots.store_product_id = sp.id
    and price_snapshots.branch_id is not null
  order by price_snapshots.captured_at desc, price_snapshots.id desc
  limit 1
) ps on true
join public.branches b on b.id = ps.branch_id
where s.enabled = true
  and b.geocoding_status in ('geocoded', 'manual')
  and b.latitude is not null
  and b.longitude is not null;

create or replace view public.compare_prices as
select
  store_product_id,
  product_id,
  product_name,
  normalized_name,
  category,
  store_id,
  store_name,
  store_slug,
  branch_id,
  branch_name,
  branch_address,
  branch_neighborhood,
  branch_postal_code,
  branch_municipality,
  branch_state,
  latitude,
  longitude,
  source_product_name,
  observation_url,
  store_product_url,
  image_url,
  presentation,
  price,
  currency,
  available,
  source,
  captured_at,
  days_old,
  freshness,
  dense_rank() over (partition by normalized_name order by price) as price_rank,
  min(price) over (partition by normalized_name) as best_price
from public.latest_prices
where available = true
  and freshness <> 'old'
  and branch_id is not null
  and latitude is not null
  and longitude is not null
  and image_url is not null
  and store_product_url is not null;

create or replace view public.direct_quality_summary as
select
  count(*)::integer as total_latest_prices,
  count(*) filter (where image_url is not null)::integer as with_image,
  count(*) filter (where store_product_url is not null)::integer as with_official_link,
  count(*) filter (where freshness = 'fresh')::integer as fresh_prices,
  count(*) filter (where freshness = 'stale')::integer as stale_prices,
  count(*) filter (where freshness = 'old')::integer as old_prices,
  count(*) filter (where price <= 0 or price > 100000)::integer as implausible_prices,
  count(distinct source)::integer as direct_sources,
  count(distinct product_id)::integer as covered_products,
  count(*) filter (where branch_id is not null)::integer as with_branch,
  count(*) filter (where latitude is not null and longitude is not null)::integer as with_coordinates
from public.latest_prices;
