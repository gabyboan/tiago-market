do $$
begin
  if exists (
    select 1
    from public.branches
    group by source, external_key
    having count(*) > 1
  ) then
    raise exception
      'Cannot create unique index public.branches(source, external_key): duplicate branch identities exist.';
  end if;
end $$;

create unique index if not exists branches_source_external_key_key
  on public.branches (source, external_key);

do $$
begin
  if exists (
    select 1
    from public.price_snapshots
    where branch_id is not null
    group by store_product_id, branch_id, captured_at
    having count(*) > 1
  ) then
    raise exception
      'Cannot create unique index public.price_snapshots(store_product_id, branch_id, captured_at): duplicate geolocated snapshots exist.';
  end if;
end $$;

create unique index if not exists price_snapshots_store_product_branch_captured_unique
  on public.price_snapshots (store_product_id, branch_id, captured_at)
  where branch_id is not null;

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
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if user_latitude is null
    or user_longitude is null
    or user_latitude < -90
    or user_latitude > 90
    or user_longitude < -180
    or user_longitude > 180 then
    raise exception 'Invalid coordinates for nearby_prices.';
  end if;

  if radius_km is null or radius_km < 0.1 or radius_km > 100 then
    raise exception 'Invalid radius_km for nearby_prices. Expected 0.1 to 100.';
  end if;

  return query
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
  join public.stores s on s.id = lp.store_id
  where s.enabled = true
    and s.country = 'MX'
    and lp.branch_id is not null
    and b.geocoding_status in ('manual', 'geocoded')
    and b.latitude between 14 and 33.5
    and b.longitude between -119 and -86
    and lp.latitude is not null
    and lp.longitude is not null
    and (
      nullif(trim(search_query), '') is null
      or lp.normalized_name ilike '%' || trim(search_query) || '%'
      or lp.product_name ilike '%' || trim(search_query) || '%'
    )
    and (source_filter is null or lp.source = source_filter)
    and (store_filter is null or lp.store_slug = store_filter)
    and (not only_available or lp.available)
    and public.distance_km(
      user_latitude,
      user_longitude,
      lp.latitude::double precision,
      lp.longitude::double precision
    ) <= radius_km
  order by 15 asc, lp.price asc
  limit 100;
end;
$$;

create or replace function public.nearby_branches(
  user_latitude double precision,
  user_longitude double precision,
  radius_km double precision default 10
)
returns table (
  branch_id uuid,
  store_name text,
  store_slug text,
  branch_name text,
  branch_address text,
  branch_municipality text,
  branch_state text,
  latitude numeric,
  longitude numeric,
  distance_km double precision
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if user_latitude is null
    or user_longitude is null
    or user_latitude < -90
    or user_latitude > 90
    or user_longitude < -180
    or user_longitude > 180 then
    raise exception 'Invalid coordinates for nearby_branches.';
  end if;

  if radius_km is null or radius_km < 0.1 or radius_km > 100 then
    raise exception 'Invalid radius_km for nearby_branches. Expected 0.1 to 100.';
  end if;

  return query
  select
    b.id as branch_id,
    s.name as store_name,
    s.slug as store_slug,
    b.name as branch_name,
    b.address as branch_address,
    b.municipality as branch_municipality,
    b.state as branch_state,
    b.latitude,
    b.longitude,
    public.distance_km(
      user_latitude,
      user_longitude,
      b.latitude::double precision,
      b.longitude::double precision
    ) as distance_km
  from public.branches b
  join public.stores s on s.id = b.store_id
  where s.enabled = true
    and s.country = 'MX'
    and b.geocoding_status in ('manual', 'geocoded')
    and b.latitude between 14 and 33.5
    and b.longitude between -119 and -86
    and public.distance_km(
      user_latitude,
      user_longitude,
      b.latitude::double precision,
      b.longitude::double precision
    ) <= radius_km
  order by 10 asc, s.name asc, b.name asc
  limit 100;
end;
$$;

create or replace function public.online_prices(
  search_query text,
  limit_count integer default 100,
  page_number integer default 1,
  category_filter text default null,
  only_available boolean default true
)
returns table (
  product_name text,
  normalized_name text,
  category text,
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
  distance_km double precision,
  store_product_url text,
  image_url text,
  presentation text
)
language sql
stable
security definer
set search_path = ''
as $$
  with latest_online as (
    select distinct on (sp.id)
      p.name as product_name,
      p.normalized_name,
      p.category,
      s.name as store_name,
      s.slug as store_slug,
      null::uuid as branch_id,
      null::text as branch_name,
      null::text as branch_address,
      null::text as branch_municipality,
      ps.price,
      ps.currency,
      ps.source,
      ps.captured_at,
      greatest(0, current_date - ps.captured_at::date)::integer as days_old,
      sp.store_product_url,
      sp.image_url,
      sp.presentation,
      ps.available
    from public.store_products sp
    join public.products p on p.id = sp.product_id
    join public.stores s on s.id = sp.store_id
    join public.price_snapshots ps on ps.store_product_id = sp.id
    where s.enabled = true
      and s.country = 'MX'
      and ps.branch_id is null
      and (
        nullif(trim(search_query), '') is null
        or p.normalized_name ilike '%' || trim(search_query) || '%'
        or p.name ilike '%' || trim(search_query) || '%'
        or ps.source_product_name ilike '%' || trim(search_query) || '%'
      )
      and (category_filter is null or p.category = category_filter)
      and (not only_available or ps.available)
    order by sp.id, ps.captured_at desc, ps.id desc
  )
  select
    product_name,
    normalized_name,
    category,
    store_name,
    store_slug,
    branch_id,
    branch_name,
    branch_address,
    branch_municipality,
    price,
    currency,
    source,
    captured_at,
    case
      when days_old < 7 then 'fresh'::text
      when days_old <= 21 then 'stale'::text
      else 'old'::text
    end as freshness,
    days_old,
    null::double precision as distance_km,
    store_product_url,
    image_url,
    presentation
  from latest_online
  order by price asc, product_name asc
  limit least(greatest(limit_count, 1), 100)
  offset greatest(page_number - 1, 0) * least(greatest(limit_count, 1), 100);
$$;

revoke all on function public.nearby_prices(
  text,
  double precision,
  double precision,
  double precision,
  text,
  text,
  boolean
) from PUBLIC;

revoke all on function public.nearby_branches(
  double precision,
  double precision,
  double precision
) from PUBLIC;

revoke all on function public.online_prices(
  text,
  integer,
  integer,
  text,
  boolean
) from PUBLIC;

grant execute on function public.nearby_prices(
  text,
  double precision,
  double precision,
  double precision,
  text,
  text,
  boolean
) to anon, authenticated;

grant execute on function public.nearby_branches(
  double precision,
  double precision,
  double precision
) to anon, authenticated;

grant execute on function public.online_prices(
  text,
  integer,
  integer,
  text,
  boolean
) to anon, authenticated;
