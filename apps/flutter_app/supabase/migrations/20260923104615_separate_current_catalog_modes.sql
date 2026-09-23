-- Explicit channel; a missing branch must never silently turn local data online.
alter table public.price_snapshots add column price_scope text;
alter table public.price_snapshots drop constraint price_snapshots_branch_required_check;

update public.price_snapshots set price_scope = case when branch_id is null then 'online' else 'branch_local' end;
alter table public.price_snapshots alter column price_scope set default 'branch_local';
alter table public.price_snapshots alter column price_scope set not null;
alter table public.price_snapshots add constraint price_snapshots_scope_check check (
  (price_scope = 'online' and branch_id is null) or
  (price_scope = 'branch_local' and branch_id is not null)
);

-- Current observations only. Historical snapshots remain untouched.
-- Internal view: callers only receive the explicitly scoped RPC results.
create or replace view public.current_catalog_prices with (security_invoker = true) as
with latest as (
  select distinct on (ps.store_product_id, ps.branch_id) ps.*
  from public.price_snapshots ps
  order by ps.store_product_id, ps.branch_id, ps.captured_at desc, ps.id desc
), evidence as (
  select ps.*, coalesce(
    case when ps.raw_payload->>'source_url' ~ '^https?://[^ /]+' then ps.raw_payload->>'source_url' end,
    case when ps.external_reference ~ '^https?://[^ /]+' then ps.external_reference end,
    case when sp.store_product_url ~ '^https?://[^ /]+' then sp.store_product_url end
  ) as evidence_url
  from latest ps join public.store_products sp on sp.id = ps.store_product_id
)
select sp.id as store_product_id, p.name as product_name, p.normalized_name,
  p.category, s.name as store_name, s.slug as store_slug,
  ps.branch_id, b.name as branch_name, b.address as branch_address,
  b.municipality as branch_municipality, b.latitude, b.longitude,
  ps.price, ps.currency, ps.available, ps.source, ps.captured_at,
  'fresh'::text as freshness,
  greatest(0, floor(extract(epoch from (now() - ps.captured_at))/86400))::integer as days_old,
  ps.evidence_url as observation_url, sp.store_product_url,
  case when sp.image_url ~ '^https?://[^ /]+' then sp.image_url end as image_url,
  sp.presentation
from evidence ps
join public.store_products sp on sp.id = ps.store_product_id
join public.products p on p.id = sp.product_id
join public.stores s on s.id = sp.store_id
left join public.branches b on b.id = ps.branch_id and b.store_id = s.id
where s.enabled and s.country = 'MX'
  and ((ps.price_scope = 'online' and ps.branch_id is null) or (ps.price_scope = 'branch_local' and ps.branch_id is not null))
  and ps.price > 0 and ps.currency = 'MXN'
  and nullif(trim(p.name),'') is not null
  and nullif(trim(s.name),'') is not null
  and nullif(trim(sp.presentation),'') is not null
  and nullif(trim(ps.source),'') is not null
  and ps.evidence_url is not null
  and ps.captured_at > now() - interval '7 days'
  and ps.captured_at <= now() + interval '5 minutes'
  and coalesce(ps.raw_payload->>'is_synthetic','false') = 'false'
  and coalesce(ps.raw_payload->>'review_status','accepted') = 'accepted'
  and (ps.raw_payload->>'valid_until' is null or (ps.raw_payload->>'valid_until')::timestamptz > now())
  and (ps.branch_id is null or (
    b.geocoding_status in ('manual','geocoded')
    and b.latitude between 14 and 33.5 and b.longitude between -119 and -86
    and nullif(trim(b.name),'') is not null and nullif(trim(b.address),'') is not null
  ));
revoke all on public.current_catalog_prices from public, anon, authenticated;

create or replace function public.online_prices_v3(search_query text,
 limit_count integer default 100, page_number integer default 1,
 category_filter text default null, only_available boolean default true,
 sort_order text default 'price_asc')
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
  presentation text
)
language plpgsql stable security definer set search_path = '' as $$
begin

 if limit_count is null or limit_count not between 1 and 100 or page_number is null or page_number not between 1 and 10000 then raise exception 'Invalid pagination'; end if;
 return query select c.product_name,c.normalized_name,c.category,c.store_name,c.store_slug,
 c.branch_id,c.branch_name,c.branch_address,c.branch_municipality,
 c.price,c.currency,c.available,c.source,c.captured_at,c.freshness,c.days_old,
 null::double precision,c.observation_url,c.store_product_url,c.image_url,c.presentation
 from public.current_catalog_prices c
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
 c.price, c.product_name, c.store_slug, c.store_product_id, c.branch_id
 limit limit_count offset (page_number - 1) * limit_count;
end; $$;
revoke all on function public.online_prices_v3(text,integer,integer,text,boolean,text) from public;
grant execute on function public.online_prices_v3(text,integer,integer,text,boolean,text) to anon, authenticated;

create or replace function public.nearby_prices_v3(search_query text, user_latitude double precision, user_longitude double precision, radius_km double precision default 10,
 limit_count integer default 100, page_number integer default 1,
 category_filter text default null, only_available boolean default true,
 sort_order text default 'price_asc')
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
  presentation text
)
language plpgsql stable security definer set search_path = '' as $$
begin
 if user_latitude is null or user_longitude is null or not(user_latitude between -90 and 90) or not(user_longitude between -180 and 180) or radius_km is null or not(radius_km between 0.1 and 100) then raise exception 'Invalid coordinates or radius'; end if;
 if limit_count is null or limit_count not between 1 and 100 or page_number is null or page_number not between 1 and 10000 then raise exception 'Invalid pagination'; end if;
 return query select c.product_name,c.normalized_name,c.category,c.store_name,c.store_slug,
 c.branch_id,c.branch_name,c.branch_address,c.branch_municipality,
 c.price,c.currency,c.available,c.source,c.captured_at,c.freshness,c.days_old,
 public.distance_km(user_latitude,user_longitude,c.latitude::double precision,c.longitude::double precision),c.observation_url,c.store_product_url,c.image_url,c.presentation
 from public.current_catalog_prices c
 where c.branch_id is not null
 and public.distance_km(user_latitude,user_longitude,c.latitude::double precision,c.longitude::double precision) <= radius_km
 and (not only_available or c.available)
 and (category_filter is null or c.category = category_filter)
 and (nullif(trim(search_query),'') is null or
   c.product_name ilike '%' || trim(search_query) || '%' or
   c.normalized_name ilike '%' || trim(search_query) || '%')
 order by
 case when sort_order = 'distance' then public.distance_km(user_latitude,user_longitude,c.latitude::double precision,c.longitude::double precision) end,
 case when sort_order = 'price_desc' then c.price end desc,
 case when sort_order = 'fresh_desc' then c.captured_at end desc,
 case when sort_order = 'name' then c.product_name end,
 c.price, c.product_name, c.store_slug, c.store_product_id, c.branch_id
 limit limit_count offset (page_number - 1) * limit_count;
end; $$;
revoke all on function public.nearby_prices_v3(text,double precision,double precision,double precision,integer,integer,text,boolean,text) from public;
grant execute on function public.nearby_prices_v3(text,double precision,double precision,double precision,integer,integer,text,boolean,text) to anon, authenticated;

create or replace function public.catalog_categories_v3(
 user_latitude double precision default null, user_longitude double precision default null,
 radius_km double precision default 10)
returns table(name text, count bigint)
language sql stable security definer set search_path = '' as $$
 select category, count(*) from public.current_catalog_prices
 where available and (
   (user_latitude is null and user_longitude is null and branch_id is null) or
   (user_latitude between -90 and 90 and user_longitude between -180 and 180
     and radius_km between 0.1 and 100 and branch_id is not null
     and public.distance_km(user_latitude,user_longitude,latitude::double precision,longitude::double precision)<=radius_km)
 ) group by category order by category;
$$;
revoke all on function public.catalog_categories_v3(double precision,double precision,double precision) from public;
grant execute on function public.catalog_categories_v3(double precision,double precision,double precision) to anon, authenticated;

-- Separate online publisher; never uses the branch-only staging publisher.
-- Only server jobs can execute it. No credentials in Flutter.
create or replace function public.publish_online_observations(records jsonb)
returns integer language plpgsql security invoker set search_path = '' as $$
declare
 r jsonb; sid uuid; pid uuid; listing uuid; inserted integer := 0; n integer;
 expected_host text; observed timestamptz;
begin
 if jsonb_typeof(records) <> 'array' or jsonb_array_length(records) not between 1 and 100 then
   raise exception 'Expected 1..100 observations';
 end if;
 -- Serialize listing upserts without relying on historical non-unique URLs.
 perform pg_catalog.pg_advisory_xact_lock(723092301);
 for r in select value from jsonb_array_elements(records) loop
   expected_host := case r->>'source'
     when 'smart-final-public-web' then 'www.smartnfinal.com.mx'
     end;
   if expected_host is null or
      (r->>'source' = 'arteli-public-web' and r->>'store_slug' is distinct from 'arteli-online') or
      (r->>'source' = 'smart-final-public-web' and r->>'store_slug' is distinct from 'smart-final-mexico-online') then
     raise exception 'Source/store not enabled';
   end if;
   if r->>'price_scope' is distinct from 'online' or r->>'branch_id' is not null or r->>'branch_external_key' is not null or r->>'branch_name' is not null
     or r->>'currency' is distinct from 'MXN' or (r->>'price')::numeric <= 0
     or jsonb_typeof(r->'price') is distinct from 'number'
     or r->>'is_synthetic' is distinct from 'false'
     or r->>'review_status' is distinct from 'accepted'
     or jsonb_typeof(r->'available') is distinct from 'boolean'
     or nullif(trim(r->>'product_name'),'') is null
     or nullif(trim(r->>'normalized_name'),'') is null
     or nullif(trim(r->>'presentation'),'') is null
     or nullif(trim(r->>'category'),'') is null
     or r->>'source_url' is distinct from r->>'store_product_url'
     or coalesce(r->>'source_url','') not like 'https://' || expected_host || '/%'
     or coalesce(r->>'response_sha256','') !~ '^[a-f0-9]{64}$'
     or coalesce(r->>'observed_at','') !~ '(Z|[+-][0-9]{2}:[0-9]{2})$'
     or (r->>'image_url' is not null and r->>'image_url' !~ '^https://[^ /]+/') then
     raise exception 'Incomplete or invalid online observation';
   end if;
   observed := (r->>'observed_at')::timestamptz;
   if observed <= now() - interval '7 days' or observed > now() + interval '5 minutes'
     or (r->>'valid_until' is not null and (r->>'valid_until')::timestamptz <= now()) then
     raise exception 'Expired or future observation';
   end if;
   select id into sid from public.stores where slug = r->>'store_slug' and country='MX' and enabled;
   if sid is null then raise exception 'Unknown store'; end if;
   insert into public.products(name, normalized_name, category)
     values(r->>'product_name',r->>'normalized_name',r->>'category')
     on conflict(normalized_name) do update set name=excluded.name, category=excluded.category
     returning id into pid;
   select id into listing from public.store_products
     where store_id=sid and (store_product_url=r->>'store_product_url' or external_url=r->>'store_product_url')
     order by id limit 1;
   if listing is null then
     insert into public.store_products(store_id,product_id,external_name,external_url,store_product_url,image_url,presentation,available,source,last_seen_at)
       values(sid,pid,r->>'product_name',r->>'store_product_url',r->>'store_product_url',r->>'image_url',r->>'presentation',(r->>'available')::boolean,r->>'source',observed)
       returning id into listing;
   else
     update public.store_products set product_id=pid, external_name=r->>'product_name',
       image_url=r->>'image_url',presentation=r->>'presentation',store_product_url=r->>'store_product_url',
       available=(r->>'available')::boolean,source=r->>'source',last_seen_at=observed
       where id=listing and (last_seen_at is null or last_seen_at <= observed);
   end if;
   insert into public.price_snapshots(store_product_id,price,currency,available,source,captured_at,
     source_product_name,source_store_name,external_reference,raw_payload,price_scope)
   select listing,(r->>'price')::numeric,'MXN',(r->>'available')::boolean,r->>'source',observed,
     r->>'product_name',s.name,r->>'source_url',r,'online' from public.stores s where s.id=sid
   on conflict do nothing;
   get diagnostics n = row_count;
   inserted := inserted+n;
 end loop;
 return inserted;
end; $$;
revoke all on function public.publish_online_observations(jsonb) from public, anon, authenticated;
grant execute on function public.publish_online_observations(jsonb) to service_role;
