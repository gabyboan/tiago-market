-- Avoid repeated JSON decompression for each fresh catalog snapshot.
-- The previous and optimized views return identical rows; retain the existing ACL.
-- Read original evidence once per latest snapshot; preserve catalog filters.
create or replace view public.current_catalog_prices with (security_invoker = true) as
with latest_ids as materialized (
  select distinct on (ps.store_product_id,ps.branch_id) ps.id
  from public.price_snapshots ps
  order by ps.store_product_id,ps.branch_id,ps.captured_at desc,ps.id desc
), metadata as materialized (
  select ps.id,ps.store_product_id,ps.branch_id,ps.price_scope,ps.price,
    ps.currency,ps.available,ps.source,ps.captured_at,ps.external_reference,
    m.source_url,m.is_synthetic,m.review_status,m.valid_until
  from latest_ids l join public.price_snapshots ps on ps.id=l.id
  cross join lateral jsonb_to_record(
    case when jsonb_typeof(ps.raw_payload)='object' then ps.raw_payload else '{}'::jsonb end
  ) as m(source_url text,is_synthetic text,review_status text,valid_until text)
  where ps.captured_at>now()-interval '7 days'
    and ps.captured_at<=now()+interval '5 minutes'
    and ps.price>0 and ps.currency='MXN'
), catalog as (
  select sp.id as store_product_id,p.name as product_name,p.normalized_name,
    p.category,s.name as store_name,s.slug as store_slug,
    ps.branch_id,b.name as branch_name,b.address as branch_address,
    b.municipality as branch_municipality,b.latitude,b.longitude,
    ps.price,ps.currency,ps.available,ps.source,ps.captured_at,
    'fresh'::text as freshness,
    greatest(0,floor(extract(epoch from(now()-ps.captured_at))/86400))::integer as days_old,
    coalesce(
      case when ps.source_url ~ '^https?://[^ /]+' then ps.source_url end,
      case when ps.external_reference ~ '^https?://[^ /]+' then ps.external_reference end,
      case when sp.store_product_url ~ '^https?://[^ /]+' then sp.store_product_url end
    ) as observation_url,
    sp.store_product_url,
    case when sp.image_url ~ '^https?://[^ /]+' then sp.image_url end as image_url,
    sp.presentation
  from metadata ps
  join public.store_products sp on sp.id=ps.store_product_id
  join public.products p on p.id=sp.product_id
  join public.stores s on s.id=sp.store_id
  left join public.branches b on b.id=ps.branch_id and b.store_id=s.id
  where s.enabled and s.country='MX'
    and ((ps.price_scope='online' and ps.branch_id is null)
      or (ps.price_scope='branch_local' and ps.branch_id is not null))
    and nullif(trim(p.name),'') is not null
    and nullif(trim(s.name),'') is not null
    and nullif(trim(sp.presentation),'') is not null
    and nullif(trim(ps.source),'') is not null
    and coalesce(ps.is_synthetic,'false')='false'
    and coalesce(ps.review_status,'accepted')='accepted'
    and (ps.valid_until is null or ps.valid_until::timestamptz>now())
    and (ps.branch_id is null or (
      b.geocoding_status in ('manual','geocoded')
      and b.latitude between 14 and 33.5 and b.longitude between -119 and -86
      and nullif(trim(b.name),'') is not null and nullif(trim(b.address),'') is not null
    ))
)
select * from catalog where observation_url is not null;
