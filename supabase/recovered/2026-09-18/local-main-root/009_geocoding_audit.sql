alter table public.branches
  drop constraint branches_geocoding_status_check;

alter table public.branches
  add constraint branches_geocoding_status_check
  check (geocoding_status in ('pending', 'geocoded', 'review', 'failed', 'manual'));

alter table public.branches
  add column geocoding_provider text,
  add column geocoding_query text,
  add column geocoding_confidence numeric(5, 4)
    check (geocoding_confidence between 0 and 1),
  add column geocoding_accuracy text,
  add column geocoding_external_id text,
  add column geocoding_payload jsonb,
  add column geocoding_error text,
  add column geocoding_attempts integer not null default 0
    check (geocoding_attempts >= 0),
  add column geocoding_last_attempt_at timestamptz;

create index branches_pending_geocoding_idx
  on public.branches (updated_at, id)
  where geocoding_status in ('pending', 'failed');

comment on column public.branches.geocoding_payload is
  'Respuesta conservada solo cuando la licencia y modo del proveedor permiten almacenamiento permanente.';

drop view public.branch_coverage_summary;

create view public.branch_coverage_summary
with (security_invoker = true)
as
select
  count(*)::integer as total_normalized_branches,
  count(*) filter (
    where geocoding_status in ('geocoded', 'manual')
      and latitude is not null
      and longitude is not null
  )::integer as total_geocoded_branches,
  count(*) filter (
    where geocoding_status = 'review'
  )::integer as total_review_geocoding,
  count(*) filter (
    where geocoding_status in ('pending', 'failed')
  )::integer as total_pending_geocoding,
  count(distinct city_code)::integer as total_city_codes
from public.branches;

grant select on table public.branch_coverage_summary to service_role;

create or replace function public.nearby_prices(
  search_query text,
  user_latitude double precision,
  user_longitude double precision,
  radius_km double precision default 10,
  source_filter text default null,
  store_filter text default null,
  only_available boolean default true
)
returns table (
  product_name text,
  normalized_name text,
  store_name text,
  store_slug text,
  branch_id uuid,
  branch_name text,
  branch_address text,
  branch_municipality text,
  price numeric,
  currency text,
  source text,
  captured_at timestamptz,
  freshness text,
  days_old integer,
  distance_km double precision
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    lp.product_name,
    lp.normalized_name,
    lp.store_name,
    lp.store_slug,
    lp.branch_id,
    lp.branch_name,
    lp.branch_address,
    lp.branch_municipality,
    lp.price,
    lp.currency,
    lp.source,
    lp.captured_at,
    lp.freshness,
    lp.days_old,
    public.distance_km(
      user_latitude,
      user_longitude,
      lp.latitude::double precision,
      lp.longitude::double precision
    ) as distance_km
  from public.latest_prices lp
  join public.branches b on b.id = lp.branch_id
  where lp.normalized_name ilike '%' || search_query || '%'
    and b.geocoding_status in ('geocoded', 'manual')
    and lp.latitude is not null
    and lp.longitude is not null
    and (source_filter is null or lp.source = source_filter)
    and (store_filter is null or lp.store_slug = store_filter)
    and (not only_available or lp.available)
    and public.distance_km(
      user_latitude,
      user_longitude,
      lp.latitude::double precision,
      lp.longitude::double precision
    ) <= radius_km
  order by distance_km asc, lp.price asc;
$$;
