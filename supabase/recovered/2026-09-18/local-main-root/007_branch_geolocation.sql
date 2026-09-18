create table public.branches (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  source text not null,
  external_key text not null,
  name text not null,
  address text,
  neighborhood text,
  postal_code text,
  municipality text,
  state text,
  city_code text,
  city_name text,
  latitude numeric(9, 6) check (latitude between -90 and 90),
  longitude numeric(9, 6) check (longitude between -180 and 180),
  geocoding_status text not null default 'pending'
    check (geocoding_status in ('pending', 'geocoded', 'failed', 'manual')),
  geocoded_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (source, external_key)
);

alter table public.store_products
  add column branch_id uuid references public.branches(id) on delete set null;

alter table public.price_snapshots
  add column branch_id uuid references public.branches(id) on delete set null;

create index branches_store_id_idx on public.branches (store_id);
create index branches_city_code_idx on public.branches (city_code);
create index branches_geocoded_idx
  on public.branches (latitude, longitude)
  where latitude is not null and longitude is not null;
create index store_products_branch_id_idx on public.store_products (branch_id);
create index price_snapshots_branch_id_idx on public.price_snapshots (branch_id);

insert into public.branches (
  store_id,
  source,
  external_key,
  name,
  address,
  neighborhood,
  postal_code,
  municipality,
  state,
  city_code,
  city_name
)
select distinct on (ps.source, branch_data.external_key)
  sp.store_id,
  ps.source,
  branch_data.external_key,
  ps.source_branch_name,
  nullif(ps.raw_payload ->> 'direccion', ''),
  nullif(ps.raw_payload ->> 'colonia', ''),
  nullif(ps.raw_payload ->> 'cp', ''),
  nullif(ps.raw_payload ->> 'municipio', ''),
  nullif(ps.raw_payload ->> 'entidad', ''),
  ps.source_city_code,
  ps.source_city_name
from public.price_snapshots ps
join public.store_products sp on sp.id = ps.store_product_id
cross join lateral (
  select md5(concat_ws(
    '|',
    ps.source,
    ps.source_city_code,
    lower(ps.source_store_name),
    lower(ps.source_branch_name)
  )) as external_key
) branch_data
where ps.source_branch_name is not null
order by ps.source, branch_data.external_key, ps.captured_at desc;

update public.store_products sp
set branch_id = b.id
from public.price_snapshots ps
join public.branches b
  on b.source = ps.source
  and b.external_key = md5(concat_ws(
    '|',
    ps.source,
    ps.source_city_code,
    lower(ps.source_store_name),
    lower(ps.source_branch_name)
  ))
where ps.store_product_id = sp.id
  and sp.branch_id is null;

update public.price_snapshots ps
set branch_id = b.id
from public.branches b
where b.source = ps.source
  and b.external_key = md5(concat_ws(
    '|',
    ps.source,
    ps.source_city_code,
    lower(ps.source_store_name),
    lower(ps.source_branch_name)
  ))
  and ps.branch_id is null;

alter table public.branches enable row level security;
revoke all on table public.branches from anon, authenticated;
grant select, insert, update on table public.branches to service_role;

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

create view public.branch_coverage_summary
with (security_invoker = true)
as
select
  count(*)::integer as total_normalized_branches,
  count(*) filter (
    where latitude is not null and longitude is not null
  )::integer as total_geocoded_branches,
  count(*) filter (
    where latitude is null or longitude is null
  )::integer as total_pending_geocoding,
  count(distinct city_code)::integer as total_city_codes
from public.branches;

create or replace function public.distance_km(
  origin_latitude double precision,
  origin_longitude double precision,
  destination_latitude double precision,
  destination_longitude double precision
)
returns double precision
language sql
immutable
strict
set search_path = ''
as $$
  select 6371 * 2 * asin(sqrt(
    power(sin(radians(destination_latitude - origin_latitude) / 2), 2) +
    cos(radians(origin_latitude)) *
    cos(radians(destination_latitude)) *
    power(sin(radians(destination_longitude - origin_longitude) / 2), 2)
  ));
$$;

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
  where lp.normalized_name ilike '%' || search_query || '%'
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

grant select on table
  public.latest_prices,
  public.compare_prices,
  public.product_coverage,
  public.branch_coverage_summary
to service_role;

grant execute on function public.nearby_prices(
  text,
  double precision,
  double precision,
  double precision,
  text,
  text,
  boolean
) to service_role;

revoke execute on function public.nearby_prices(
  text,
  double precision,
  double precision,
  double precision,
  text,
  text,
  boolean
) from anon, authenticated;

revoke execute on function public.distance_km(
  double precision,
  double precision,
  double precision,
  double precision
) from public, anon, authenticated;

grant execute on function public.distance_km(
  double precision,
  double precision,
  double precision,
  double precision
) to service_role;

comment on table public.branches is
  'Sucursales normalizadas; las coordenadas deben provenir de geocodificación autorizada o carga manual.';
