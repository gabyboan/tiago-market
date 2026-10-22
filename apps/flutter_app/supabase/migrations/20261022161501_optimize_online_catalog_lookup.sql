-- Read latest online observation facts without loading historical evidence.
create index if not exists price_snapshots_online_catalog_lookup_idx
on public.price_snapshots (store_product_id, captured_at desc, id desc)
include (price, currency, available, source, price_scope)
where branch_id is null;

-- Keep the existing contract; defer evidence decoding until after price ordering.
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
language plpgsql stable security definer
set search_path = ''
set plan_cache_mode = force_custom_plan as $$
begin
  if limit_count is null or limit_count not between 1 and 100
    or page_number is null or page_number not between 1 and 10000 then
    raise exception 'Invalid pagination';
  end if;

  return query
with matching_products as materialized (
  select p.id, p.name, p.normalized_name, p.category, p.brand, p.gtin,
    p.variant_label, p.net_quantity, p.unit, p.pack_count, p.canonical_variant_key
  from public.products p
  where nullif(trim(p.name), '') is not null and p.normalized_name is not null
    and (category_filter is null or p.category = category_filter)
    and (nullif(trim(search_query), '') is null
      or p.name ilike '%' || trim(search_query) || '%'
      or p.normalized_name ilike '%' || trim(search_query) || '%')
), matching_stores as materialized (
  select s.id, s.name, s.slug from public.stores s
  where s.enabled and s.country = 'MX' and nullif(trim(s.name), '') is not null
), candidates as materialized (
  select sp.id as store_product_id, ps.id as snapshot_id,
    p.name as product_name, p.normalized_name, p.category,
    s.name as store_name, s.slug as store_slug,
    ps.price, ps.currency, ps.available, ps.source, ps.captured_at,
    sp.store_product_url, sp.image_url, sp.presentation,
    p.brand, p.gtin, p.variant_label, p.net_quantity, p.unit, p.pack_count,
    p.canonical_variant_key,
    case when sort_order = 'price_desc' then ps.price end as descending_price,
    case when sort_order = 'fresh_desc' then ps.captured_at end as descending_capture,
    case when sort_order = 'name' then p.name end as ordered_name
  from public.store_products sp
  join matching_products p on p.id = sp.product_id
  join matching_stores s on s.id = sp.store_id
  cross join lateral (
    select snap.id, snap.price, snap.currency, snap.available, snap.source,
      snap.captured_at, snap.price_scope
    from public.price_snapshots snap
    where snap.store_product_id = sp.id and snap.branch_id is null
    order by snap.captured_at desc, snap.id desc
    limit 1
  ) ps
  where ps.price_scope = 'online'
    and ps.captured_at > now() - interval '7 days'
    and ps.captured_at <= now() + interval '5 minutes'
    and ps.price > 0 and ps.currency = 'MXN'
    and (not only_available or ps.available)
    and nullif(trim(sp.presentation), '') is not null
    and nullif(trim(ps.source), '') is not null
)
select c.product_name, c.normalized_name, c.category, c.store_name, c.store_slug,
  null::uuid as branch_id, null::text as branch_name, null::text as branch_address,
  null::text as branch_municipality, c.price, c.currency, c.available, c.source,
  c.captured_at, 'fresh'::text as freshness,
  greatest(0, floor(extract(epoch from (now() - c.captured_at)) / 86400))::integer as days_old,
  null::double precision as distance_km,
  coalesce(
    case when m.source_url ~ '^https?://[^ /]+' then m.source_url end,
    case when m.external_reference ~ '^https?://[^ /]+' then m.external_reference end,
    case when c.store_product_url ~ '^https?://[^ /]+' then c.store_product_url end
  ) as observation_url,
  c.store_product_url,
  case when c.image_url ~ '^https?://[^ /]+' then c.image_url end as image_url,
  c.presentation, c.brand, c.gtin, c.variant_label, c.net_quantity, c.unit,
  c.pack_count, c.canonical_variant_key,
  (select count(*) from public.product_images i
    where i.store_product_id = c.store_product_id)::bigint as image_count
from (
  -- Retain this ordering barrier so LIMIT stops after enough eligible results.
  select ordered_candidates.* from candidates ordered_candidates
  order by ordered_candidates.descending_price desc, ordered_candidates.descending_capture desc,
    ordered_candidates.ordered_name, ordered_candidates.price, ordered_candidates.product_name,
    ordered_candidates.store_slug, ordered_candidates.store_product_id
  offset 0
) c
cross join lateral (
  -- Read and decode only the selected candidate's evidence, once per candidate.
  select facts.*, snapshot.external_reference
  from public.price_snapshots snapshot
  cross join lateral jsonb_to_record(
    case when jsonb_typeof(snapshot.raw_payload) = 'object'
      then snapshot.raw_payload else '{}'::jsonb end
  ) as facts(source_url text, is_synthetic text, review_status text, valid_until text)
  where snapshot.id = c.snapshot_id
    and coalesce(facts.is_synthetic, 'false') = 'false'
    and coalesce(facts.review_status, 'accepted') = 'accepted'
    and (facts.valid_until is null or facts.valid_until::timestamptz > now())
  offset 0
) m
where coalesce(
    case when m.source_url ~ '^https?://[^ /]+' then m.source_url end,
    case when m.external_reference ~ '^https?://[^ /]+' then m.external_reference end,
    case when c.store_product_url ~ '^https?://[^ /]+' then c.store_product_url end
  ) is not null
order by c.descending_price desc, c.descending_capture desc, c.ordered_name,
  c.price, c.product_name, c.store_slug, c.store_product_id
limit limit_count offset (page_number - 1) * limit_count;

end;
$$;

revoke all on function public.online_prices_v4(text,integer,integer,text,boolean,text) from public;
grant execute on function public.online_prices_v4(text,integer,integer,text,boolean,text) to anon, authenticated;
