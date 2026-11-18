-- Preserve category counts and evidence filters while avoiding branch/history work online.
create or replace function public.catalog_categories_v3(
  user_latitude double precision default null,
  user_longitude double precision default null,
  radius_km double precision default 10
)
returns table(name text, count bigint)
language plpgsql stable security definer
set search_path = ''
set plan_cache_mode = force_custom_plan
set statement_timeout = '20s' as $$
begin
  if user_latitude is null and user_longitude is null then
    return query
with candidates as materialized (
select p.category, sp.store_product_url, ps.id as snapshot_id
from public.store_products sp
join public.products p on p.id=sp.product_id
join public.stores s on s.id=sp.store_id
cross join lateral (
 select snap.id,snap.price,snap.currency,snap.available,snap.source,snap.captured_at,snap.price_scope
 from public.price_snapshots snap
 where snap.store_product_id=sp.id and snap.branch_id is null
 order by snap.captured_at desc,snap.id desc limit 1
) ps
where s.enabled and s.country='MX' and nullif(trim(s.name),'') is not null
and nullif(trim(p.name),'') is not null
and nullif(trim(sp.presentation),'') is not null and nullif(trim(ps.source),'') is not null
and ps.price_scope='online' and ps.price>0 and ps.currency='MXN' and ps.available
and ps.captured_at>now()-interval '7 days' and ps.captured_at<=now()+interval '5 minutes'
)
select c.category,count(*)::bigint as product_count from candidates c
cross join lateral (
select facts.*, snapshot.external_reference from public.price_snapshots snapshot
cross join lateral jsonb_to_record(case when jsonb_typeof(snapshot.raw_payload)='object' then snapshot.raw_payload else '{}'::jsonb end)
as facts(source_url text,is_synthetic text,review_status text,valid_until text)
where snapshot.id=c.snapshot_id
and coalesce(facts.is_synthetic,'false')='false'
and coalesce(facts.review_status,'accepted')='accepted'
and (facts.valid_until is null or facts.valid_until::timestamptz>now())
offset 0
) m
where coalesce(
case when m.source_url ~ '^https?://[^ /]+' then m.source_url end,
case when m.external_reference ~ '^https?://[^ /]+' then m.external_reference end,
case when c.store_product_url ~ '^https?://[^ /]+' then c.store_product_url end
) is not null
group by c.category order by c.category;
  else
    return query
    select catalog.category, count(*) from public.current_catalog_prices catalog
    where catalog.available
      and user_latitude between -90 and 90
      and user_longitude between -180 and 180
      and radius_km between 0.1 and 100
      and catalog.branch_id is not null
      and public.distance_km(user_latitude,user_longitude,
        catalog.latitude::double precision,catalog.longitude::double precision)<=radius_km
    group by catalog.category order by catalog.category;
  end if;
end;
$$;
revoke all on function public.catalog_categories_v3(double precision,double precision,double precision) from public;
grant execute on function public.catalog_categories_v3(double precision,double precision,double precision) to anon, authenticated;
notify pgrst, 'reload schema';

