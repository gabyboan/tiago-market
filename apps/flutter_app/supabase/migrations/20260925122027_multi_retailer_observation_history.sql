-- Incremental online ingestion contract. Apply only after review; no remote writes
-- are performed by the accompanying local contract tests.
alter table ingestion.source_catalog
  add column publisher_source text,
  add column online_store_slug text,
  add column allowed_product_hosts text[] not null default '{}',
  add column publisher_enabled boolean not null default false;
create unique index source_catalog_publisher_source_unique
  on ingestion.source_catalog(publisher_source) where publisher_source is not null;

-- Reuse the existing source registry. Enabling publication is independent of
-- scheduling and never starts requests to a retailer.
insert into ingestion.source_catalog(source_slug,country_code,store_brand,vertical,
  capture_scope,geolocatable,priority,status,official_domain,robots_url,notes)
values ('smart-final-mx','MX','Smart & Final México','supermercado','online',false,
  13,'validated','www.smartnfinal.com.mx','https://www.smartnfinal.com.mx/robots.txt',
  'Public product page observations; no physical branch attribution.')
on conflict(source_slug) do nothing;
update ingestion.source_catalog set
  publisher_source = config.source,
  online_store_slug = config.store_slug,
  allowed_product_hosts = config.hosts,
  publisher_enabled = true
from (values
  ('smart-final-mx','smart-final-public-web','smart-final-mexico-online',array['www.smartnfinal.com.mx']),
  ('chedraui-mx','chedraui-mx','chedraui-online',array['www.chedraui.com.mx','chedraui.com.mx']),
  ('merco-mx','merco-mx','merco-monterrey-online',array['adomicilio.merco.mx'])
) config(slug,source,store_slug,hosts)
where source_catalog.source_slug=config.slug;

alter table public.store_products add column external_id text;
create index store_products_store_external_id_idx
  on public.store_products(store_id,external_id) where external_id is not null;
create index store_products_store_url_idx
  on public.store_products(store_id,store_product_url) where store_product_url is not null;

alter table public.price_snapshots
  add column last_seen_at timestamptz,
  add column regular_price numeric(10,2),
  add column promotion_price numeric(10,2),
  add column promotion_description text,
  add column membership_required boolean not null default false,
  add column membership_price numeric(10,2),
  add column stock_status text,
  add column source_type text,
  add column extraction_method text,
  add column confidence_score numeric(5,4);
update public.price_snapshots set last_seen_at=captured_at;
-- Nullable for the old direct SQL writers: reads coalesce to captured_at.
alter table public.price_snapshots
  add constraint price_snapshots_last_seen_check check(last_seen_at>=captured_at),
  add constraint price_snapshots_offer_prices_check check(
    (regular_price is null or regular_price>0) and
    (promotion_price is null or promotion_price>0) and
    (membership_price is null or membership_price>0) and
    (regular_price is null or promotion_price is null or promotion_price<=regular_price)),
  add constraint price_snapshots_stock_status_check check(stock_status in ('in_stock','out_of_stock','unknown')),
  add constraint price_snapshots_confidence_check check(confidence_score between 0 and 1);
create index price_snapshots_current_state_idx
  on public.price_snapshots(store_product_id,branch_id,captured_at desc,id desc);
comment on column public.price_snapshots.last_seen_at is
  'Latest real observation of this price/availability/offer state. captured_at remains its first observation.';

-- Canonical, checksum-verified GTIN; invalid identifiers must be omitted by the
-- normalizer, never replaced by SKU or digits guessed from image URLs.
create function ingestion.canonical_gtin(value text)
returns text language plpgsql immutable strict security invoker set search_path='' as $$
declare total integer:=0; pos integer; weight integer:=3; digit integer;
begin
  if value !~ '^([0-9]{8}|[0-9]{12}|[0-9]{13}|[0-9]{14})$' then return null; end if;
  for pos in reverse length(value)-1..1 loop
    total:=total+substring(value,pos,1)::integer*weight;
    weight:=4-weight;
  end loop;
  digit:=(10-total%10)%10;
  if digit<>right(value,1)::integer then return null; end if;
  return lpad(value,14,'0');
end $$;
revoke all on function ingestion.canonical_gtin(text) from public,anon,authenticated;
grant execute on function ingestion.canonical_gtin(text) to service_role;

create or replace function public.publish_online_observations(records jsonb)
returns integer language plpgsql security invoker set search_path='' as $$
declare
  r jsonb; sid uuid; pid uuid; listing uuid; previous public.price_snapshots%rowtype;
  existing_product public.products%rowtype; inserted integer:=0; n integer;
  observed timestamptz; hosts text[]; source_host text; canonical_gtin text;
  identity_key text; normalized text; economic_state jsonb; previous_state jsonb;
  previous_seen timestamptz;
begin
  if records is null or jsonb_typeof(records)<>'array' then
    raise exception 'Expected 1..100 observations';
  end if;
  if jsonb_array_length(records) not between 1 and 100 then
    raise exception 'Expected 1..100 observations';
  end if;
  -- Same transaction lock as the legacy publisher; prevents duplicate listings
  -- while historical URLs are not unique. Batches are bounded to 100.
  perform pg_catalog.pg_advisory_xact_lock(723092301);
  for r in select value from jsonb_array_elements(records) loop
    if jsonb_typeof(r)<>'object' then raise exception 'Invalid observation object'; end if;
    select c.allowed_product_hosts into hosts from ingestion.source_catalog c
      where c.publisher_source=r->>'source' and c.online_store_slug=r->>'store_slug'
        and c.publisher_enabled and c.status<>'blocked' and c.country_code='MX';
    if hosts is null or cardinality(hosts)=0 then raise exception 'Source/store not enabled'; end if;
    source_host:=substring(r->>'source_url' from '^https://([a-zA-Z0-9.-]+)/');
    if r->>'price_scope' is distinct from 'online'
      or exists(select 1 from jsonb_each_text(r) x where x.key in
        ('branch_id','branch_external_key','branch_name','branch_address','branch_municipality',
         'branch_state','latitude','longitude') and x.value is not null)
      or r->>'currency' is distinct from 'MXN'
      or jsonb_typeof(r->'price') is distinct from 'number'
      or r->>'is_synthetic' is distinct from 'false'
      or r->>'review_status' is distinct from 'accepted'
      or jsonb_typeof(r->'available') is distinct from 'boolean'
      or nullif(trim(r->>'product_name'),'') is null
      or nullif(trim(r->>'normalized_name'),'') is null
      or nullif(trim(r->>'presentation'),'') is null
      or nullif(trim(r->>'category'),'') is null
      or r->>'source_url' is distinct from r->>'store_product_url'
      or source_host is null or not(lower(source_host)=any(hosts))
      or r->>'source_url' ~ '[[:space:]]'
      or coalesce(r->>'response_sha256','') !~ '^[a-f0-9]{64}$'
      or coalesce(r->>'observed_at','') !~ '(Z|[+-][0-9]{2}:[0-9]{2})$'
      or (r->>'image_url' is not null and r->>'image_url' !~ '^https://[^ /]+/') then
      raise exception 'Incomplete or invalid online observation';
    end if;
    if (r->>'price')::numeric<=0 or (r->>'price')::numeric<>round((r->>'price')::numeric,2)
      or (r->>'confidence_score' is not null and
          not((r->>'confidence_score')::numeric between 0.70 and 1))
      or (r->>'membership_required' is not null and
          jsonb_typeof(r->'membership_required') is distinct from 'boolean')
      or (r->>'pack_count' is not null and
          ((r->>'pack_count')::numeric<1 or (r->>'pack_count')::numeric<>trunc((r->>'pack_count')::numeric)))
      or (r->>'net_quantity' is not null and (r->>'net_quantity')::numeric<=0)
      or (r->>'stock_status'='in_stock' and not(r->>'available')::boolean)
      or (r->>'stock_status'='out_of_stock' and (r->>'available')::boolean) then
      raise exception 'Invalid offer metadata';
    end if;
    observed:=(r->>'observed_at')::timestamptz;
    if observed<=now()-interval '7 days' or observed>now()+interval '5 minutes'
      or (r->>'valid_until' is not null and (r->>'valid_until')::timestamptz<=now()) then
      raise exception 'Expired or future observation';
    end if;
    canonical_gtin:=ingestion.canonical_gtin(nullif(r->>'gtin',''));
    if nullif(r->>'gtin','') is not null and canonical_gtin is null then
      raise exception 'Invalid GTIN checksum';
    end if;
    identity_key:=nullif(r->>'canonical_variant_key','');
    select id into sid from public.stores where slug=r->>'store_slug' and country='MX' and enabled;
    if sid is null then raise exception 'Unknown store'; end if;
    select sp.id into listing from public.store_products sp
      where sp.store_id=sid and sp.branch_id is null and
        (sp.store_product_url=r->>'store_product_url' or sp.external_url=r->>'store_product_url'
         or (nullif(r->>'external_id','') is not null and sp.external_id=r->>'external_id'))
      order by sp.id limit 1;
    select ps.* into previous from public.price_snapshots ps
      where ps.store_product_id=listing and ps.branch_id is null
      order by ps.captured_at desc,ps.id desc limit 1;
    previous_seen:=coalesce(previous.last_seen_at,previous.captured_at);
    -- Do not let late/replayed observations overwrite newer evidence or create
    -- artificial changes in history. Their raw captures remain in staging.
    if previous_seen is not null and observed<previous_seen then continue; end if;
    economic_state:=jsonb_build_array((r->>'price')::numeric,(r->>'available')::boolean,r->>'source',
      (r->>'regular_price')::numeric,(r->>'promotion_price')::numeric,r->>'promotion_description',
      coalesce((r->>'membership_required')::boolean,false),(r->>'membership_price')::numeric,
      r->>'stock_status',r->>'valid_until');
    previous_state:=jsonb_build_array(previous.price,previous.available,previous.source,
      previous.regular_price,previous.promotion_price,previous.promotion_description,
      previous.membership_required,previous.membership_price,previous.stock_status,previous.raw_payload->>'valid_until');
    if observed=previous_seen and previous.id is not null then
      if economic_state<>previous_state then raise exception 'Conflicting observation at the same timestamp'; end if;
      continue;
    end if;

    -- Exact verified GTIN and explicitly reviewed keys are the only cross-store
    -- auto-merges. A matching title alone never joins two new retailer listings.
    pid:=null;
    if canonical_gtin is not null then
      select p.id into pid from public.products p
        where p.gtin in (canonical_gtin,substring(canonical_gtin from 2),
          substring(canonical_gtin from 3),substring(canonical_gtin from 7))
          and ingestion.canonical_gtin(p.gtin)=canonical_gtin
        order by p.id limit 1;
    end if;
    if pid is null and identity_key like 'reviewed:%' then
      select p.id into pid from public.products p where p.canonical_variant_key=identity_key order by p.id limit 1;
    end if;
    if pid is null and listing is not null then
      select sp.product_id into pid from public.store_products sp where sp.id=listing;
    end if;
    if pid is not null then
      select p.* into existing_product from public.products p where p.id=pid;
      if (canonical_gtin is not null and existing_product.gtin is not null and
          ingestion.canonical_gtin(existing_product.gtin) is distinct from canonical_gtin)
        or (r->>'pack_count' is not null and existing_product.pack_count is not null
          and (r->>'pack_count')::integer<>existing_product.pack_count)
        or (r->>'net_quantity' is not null and existing_product.net_quantity is not null
          and ((r->>'net_quantity')::numeric<>existing_product.net_quantity
               or (r->>'unit' is not null and existing_product.unit is not null and r->>'unit'<>existing_product.unit))) then
        raise exception 'Conflicting product identity; manual review required';
      end if;
      update public.products p set
        brand=coalesce(p.brand,nullif(r->>'brand','')),gtin=coalesce(p.gtin,canonical_gtin),
        variant_label=coalesce(p.variant_label,nullif(r->>'variant_label','')),
        net_quantity=coalesce(p.net_quantity,(r->>'net_quantity')::numeric),unit=coalesce(p.unit,r->>'unit'),
        pack_count=coalesce(p.pack_count,(r->>'pack_count')::integer),
        canonical_variant_key=coalesce(p.canonical_variant_key,identity_key)
      where p.id=pid;
    else
      normalized:=r->>'normalized_name';
      if exists(select 1 from public.products p where p.normalized_name=normalized) then
        normalized:=normalized||' ['||(r->>'store_slug')||':'||md5(r->>'store_product_url')||']';
      end if;
      insert into public.products(name,normalized_name,category,brand,gtin,variant_label,
        net_quantity,unit,pack_count,canonical_variant_key)
      values(r->>'product_name',normalized,r->>'category',r->>'brand',canonical_gtin,r->>'variant_label',
        (r->>'net_quantity')::numeric,r->>'unit',(r->>'pack_count')::integer,identity_key)
      returning id into pid;
    end if;
    if listing is null then
      insert into public.store_products(store_id,product_id,external_name,external_url,store_product_url,
        image_url,presentation,available,source,last_seen_at,external_id)
      values(sid,pid,r->>'product_name',r->>'store_product_url',r->>'store_product_url',r->>'image_url',
        r->>'presentation',(r->>'available')::boolean,r->>'source',observed,nullif(r->>'external_id',''))
      returning id into listing;
    else
      update public.store_products set product_id=pid,external_name=r->>'product_name',
        image_url=coalesce(r->>'image_url',image_url),presentation=r->>'presentation',
        store_product_url=r->>'store_product_url',available=(r->>'available')::boolean,
        source=r->>'source',last_seen_at=greatest(last_seen_at,observed),
        external_id=coalesce(nullif(r->>'external_id',''),external_id)
      where id=listing;
    end if;
    if previous.id is not null and economic_state=previous_state then
      update public.price_snapshots set last_seen_at=observed,raw_payload=r,
        source_type=r->>'source_type',extraction_method=r->>'extraction_method',
        confidence_score=(r->>'confidence_score')::numeric
      where id=previous.id;
    else
      insert into public.price_snapshots(store_product_id,price,currency,available,source,captured_at,
        source_product_name,source_store_name,external_reference,raw_payload,price_scope,last_seen_at,
        regular_price,promotion_price,promotion_description,membership_required,membership_price,
        stock_status,source_type,extraction_method,confidence_score)
      select listing,(r->>'price')::numeric,'MXN',(r->>'available')::boolean,r->>'source',observed,
        r->>'product_name',s.name,r->>'source_url',r,'online',observed,
        (r->>'regular_price')::numeric,(r->>'promotion_price')::numeric,r->>'promotion_description',
        coalesce((r->>'membership_required')::boolean,false),(r->>'membership_price')::numeric,
        r->>'stock_status',r->>'source_type',r->>'extraction_method',(r->>'confidence_score')::numeric
      from public.stores s where s.id=sid;
      get diagnostics n=row_count;
      inserted:=inserted+n;
    end if;
  end loop;
  return inserted;
end $$;
revoke all on function public.publish_online_observations(jsonb) from public,anon,authenticated;
grant execute on function public.publish_online_observations(jsonb) to service_role;
