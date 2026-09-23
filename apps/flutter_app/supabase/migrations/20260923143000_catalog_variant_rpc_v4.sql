-- Additive read contract for structured product variants and image coverage.
create or replace function public.online_prices_v4(
  search_query text,
  limit_count integer default 100,
  page_number integer default 1,
  category_filter text default null,
  only_available boolean default true,
  sort_order text default 'price_asc'
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
  available boolean,
  source text,
  captured_at timestamptz,
  freshness text,
  days_old integer,
  distance_km double precision,
  observation_url text,
  store_product_url text,
  image_url text,
  presentation text,
  brand text,
  gtin text,
  variant_label text,
  net_quantity numeric,
  unit text,
  pack_count integer,
  canonical_variant_key text,
  image_count bigint
)
language plpgsql stable security definer set search_path = '' as $$
begin
  if limit_count is null or limit_count not between 1 and 100
    or page_number is null or page_number not between 1 and 10000 then
    raise exception 'Invalid pagination';
  end if;

  return query
  select c.product_name,c.normalized_name,c.category,c.store_name,c.store_slug,
    c.branch_id,c.branch_name,c.branch_address,c.branch_municipality,
    c.price,c.currency,c.available,c.source,c.captured_at,c.freshness,c.days_old,
    null::double precision,c.observation_url,c.store_product_url,c.image_url,
    c.presentation,p.brand,p.gtin,p.variant_label,p.net_quantity,p.unit,
    p.pack_count,p.canonical_variant_key,
    (select count(*) from public.product_images i
      where i.store_product_id = c.store_product_id)::bigint
  from public.current_catalog_prices c
  join public.products p on p.normalized_name = c.normalized_name
  where c.branch_id is null
    and (not only_available or c.available)
    and (category_filter is null or c.category = category_filter)
    and (nullif(trim(search_query),'') is null or
      c.product_name ilike '%' || trim(search_query) || '%' or
      c.normalized_name ilike '%' || trim(search_query) || '%')
  order by
    case when sort_order = 'price_desc' then c.price end desc,
    case when sort_order = 'fresh_desc' then c.captured_at end desc,
    case when sort_order = 'name' then c.product_name end,
    c.price,c.product_name,c.store_slug,c.store_product_id,c.branch_id
  limit limit_count offset (page_number - 1) * limit_count;
end;
$$;

create or replace function public.nearby_prices_v4(
  search_query text,
  user_latitude double precision,
  user_longitude double precision,
  radius_km double precision default 10,
  limit_count integer default 100,
  page_number integer default 1,
  category_filter text default null,
  only_available boolean default true,
  sort_order text default 'price_asc'
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
  available boolean,
  source text,
  captured_at timestamptz,
  freshness text,
  days_old integer,
  distance_km double precision,
  observation_url text,
  store_product_url text,
  image_url text,
  presentation text,
  brand text,
  gtin text,
  variant_label text,
  net_quantity numeric,
  unit text,
  pack_count integer,
  canonical_variant_key text,
  image_count bigint
)
language plpgsql stable security definer set search_path = '' as $$
begin
  if user_latitude is null or user_longitude is null
    or not (user_latitude between -90 and 90)
    or not (user_longitude between -180 and 180)
    or radius_km is null or not (radius_km between 0.1 and 100) then
    raise exception 'Invalid coordinates or radius';
  end if;
  if limit_count is null or limit_count not between 1 and 100
    or page_number is null or page_number not between 1 and 10000 then
    raise exception 'Invalid pagination';
  end if;

  return query
  select c.product_name,c.normalized_name,c.category,c.store_name,c.store_slug,
    c.branch_id,c.branch_name,c.branch_address,c.branch_municipality,
    c.price,c.currency,c.available,c.source,c.captured_at,c.freshness,c.days_old,
    public.distance_km(user_latitude,user_longitude,c.latitude::double precision,
      c.longitude::double precision),c.observation_url,c.store_product_url,
    c.image_url,c.presentation,p.brand,p.gtin,p.variant_label,p.net_quantity,
    p.unit,p.pack_count,p.canonical_variant_key,
    (select count(*) from public.product_images i
      where i.store_product_id = c.store_product_id)::bigint
  from public.current_catalog_prices c
  join public.products p on p.normalized_name = c.normalized_name
  where c.branch_id is not null
    and public.distance_km(user_latitude,user_longitude,
      c.latitude::double precision,c.longitude::double precision) <= radius_km
    and (not only_available or c.available)
    and (category_filter is null or c.category = category_filter)
    and (nullif(trim(search_query),'') is null or
      c.product_name ilike '%' || trim(search_query) || '%' or
      c.normalized_name ilike '%' || trim(search_query) || '%')
  order by
    case when sort_order = 'distance' then public.distance_km(
      user_latitude,user_longitude,c.latitude::double precision,
      c.longitude::double precision) end,
    case when sort_order = 'price_desc' then c.price end desc,
    case when sort_order = 'fresh_desc' then c.captured_at end desc,
    case when sort_order = 'name' then c.product_name end,
    c.price,c.product_name,c.store_slug,c.store_product_id,c.branch_id
  limit limit_count offset (page_number - 1) * limit_count;
end;
$$;

revoke all on function public.online_prices_v4(text,integer,integer,text,boolean,text) from public;
grant execute on function public.online_prices_v4(text,integer,integer,text,boolean,text) to anon, authenticated;
revoke all on function public.nearby_prices_v4(text,double precision,double precision,double precision,integer,integer,text,boolean,text) from public;
grant execute on function public.nearby_prices_v4(text,double precision,double precision,double precision,integer,integer,text,boolean,text) to anon, authenticated;