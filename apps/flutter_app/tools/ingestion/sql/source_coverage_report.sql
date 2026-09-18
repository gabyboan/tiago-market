\pset pager off
\pset null '—'

with known_sources as (
  select source_slug as source
  from ingestion.source_catalog
  union
  select source from public.store_products
  union
  select source from public.price_snapshots
  union
  select source from public.branches
),
branch_counts as (
  select
    source,
    count(*)::integer as branches_total,
    count(*) filter (
      where geocoding_status in ('manual', 'geocoded')
        and latitude between 14 and 33.5
        and longitude between -119 and -86
    )::integer as branches_with_coordinates
  from public.branches
  group by source
),
snapshot_counts as (
  select
    ps.source,
    count(*)::integer as prices_total,
    count(*) filter (where ps.branch_id is not null)::integer
      as branch_prices,
    count(*) filter (where ps.branch_id is null)::integer
      as online_prices,
    count(distinct ps.branch_id) filter (where ps.branch_id is not null)::integer
      as branches_with_snapshots,
    count(distinct sp.product_id)::integer as products,
    max(ps.captured_at) as latest_capture,
    count(*) filter (
      where ps.price <= 0 or ps.price > 100000
    )::integer as implausible_prices,
    count(*) filter (
      where ps.branch_id is not null
        and (
          b.id is null
          or b.geocoding_status not in ('manual', 'geocoded')
          or b.latitude is null
          or b.longitude is null
          or b.latitude not between 14 and 33.5
          or b.longitude not between -119 and -86
        )
    )::integer as branch_prices_without_valid_coordinates
  from public.price_snapshots ps
  join public.store_products sp on sp.id = ps.store_product_id
  left join public.branches b on b.id = ps.branch_id
  group by ps.source
),
latest_listing_quality as (
  select
    source,
    count(*)::integer as latest_listings,
    count(*) filter (
      where store_product_url is null or store_product_url !~* '^https?://'
    )::integer as latest_without_official_url,
    count(*) filter (where image_url is null)::integer as latest_without_image
  from (
    select distinct on (ps.source, ps.store_product_id, ps.branch_id)
      ps.source,
      ps.store_product_id,
      ps.branch_id,
      sp.store_product_url,
      sp.image_url
    from public.price_snapshots ps
    join public.store_products sp on sp.id = ps.store_product_id
    order by
      ps.source,
      ps.store_product_id,
      ps.branch_id,
      ps.captured_at desc,
      ps.id desc
  ) latest
  group by source
),
matrix as (
  select
    sources.source,
    case
      when coalesce(snap.branch_prices, 0) > 0
        and coalesce(branches.branches_with_coordinates, 0) > 0
        then 'branch_local'
      when coalesce(snap.online_prices, 0) > 0
        and coalesce(snap.branch_prices, 0) = 0
        then 'online_only'
      when catalog.status = 'blocked'
        or (
          coalesce(snap.prices_total, 0) = 0
          and coalesce(catalog.status, 'candidate') not in ('candidate', 'validated')
        )
        then 'inactive'
      else 'experimental'
    end as mode,
    coalesce(catalog.capture_scope, 'unregistered') as declared_scope,
    coalesce(catalog.status, 'unregistered') as catalog_status,
    coalesce(branches.branches_with_coordinates, 0) as branches_with_coordinates,
    coalesce(snap.branches_with_snapshots, 0) as branches_with_snapshots,
    coalesce(snap.products, 0) as products,
    coalesce(snap.prices_total, 0) as prices,
    snap.latest_capture,
    case
      when snap.latest_capture is null then 'no_data'
      when snap.latest_capture >= now() - interval '7 days' then 'fresh'
      when snap.latest_capture >= now() - interval '21 days' then 'stale'
      else 'old'
    end as freshness,
    case
      when coalesce(snap.implausible_prices, 0) > 0 then 'invalid_prices'
      when coalesce(snap.branch_prices_without_valid_coordinates, 0) > 0
        then 'invalid_branch_evidence'
      when coalesce(quality.latest_without_official_url, 0) > 0
        then 'missing_official_urls'
      when coalesce(quality.latest_without_image, 0) > 0
        then 'incomplete_images'
      when coalesce(snap.prices_total, 0) = 0 then 'no_observations'
      else 'ok'
    end as quality,
    concat_ws(
      '; ',
      case
        when coalesce(snap.prices_total, 0) = 0 then 'no snapshots'
      end,
      case
        when catalog.capture_scope = 'branch'
          and coalesce(snap.branch_prices, 0) = 0
          then 'declared branch source without branch snapshots'
      end,
      case
        when coalesce(snap.online_prices, 0) > 0
          and coalesce(snap.branch_prices, 0) = 0
          then 'online prices have no branch_id evidence'
      end,
      case
        when coalesce(snap.branch_prices_without_valid_coordinates, 0) > 0
          then format(
            '%s branch snapshots lack valid coordinates',
            snap.branch_prices_without_valid_coordinates
          )
      end,
      case
        when snap.latest_capture < now() - interval '21 days'
          then 'latest capture is older than 21 days'
      end,
      case
        when coalesce(snap.implausible_prices, 0) > 0
          then format('%s implausible prices', snap.implausible_prices)
      end,
      case
        when coalesce(quality.latest_without_official_url, 0) > 0
          then format(
            '%s latest listings lack official URL',
            quality.latest_without_official_url
          )
      end
    ) as blockers
  from known_sources sources
  left join ingestion.source_catalog catalog
    on catalog.source_slug = sources.source
  left join branch_counts branches on branches.source = sources.source
  left join snapshot_counts snap on snap.source = sources.source
  left join latest_listing_quality quality on quality.source = sources.source
)
select
  source,
  mode,
  declared_scope,
  catalog_status,
  branches_with_coordinates,
  branches_with_snapshots,
  products,
  prices,
  latest_capture,
  freshness,
  quality,
  nullif(blockers, '') as blockers
from matrix
order by
  case mode
    when 'branch_local' then 1
    when 'online_only' then 2
    when 'experimental' then 3
    else 4
  end,
  source;
