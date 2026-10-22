-- Isolated test schema only. Never initialize fixtures in the project database.
do $$ begin
  if current_database() <> 'tiago_catalog_test' then
    raise exception 'Catalog fixtures require the isolated tiago_catalog_test database';
  end if;
  if not exists(select 1 from pg_roles where rolname='anon') then create role anon; end if;
  if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if;
end $$;
create table public.stores(id uuid primary key default gen_random_uuid(), name text, slug text unique, country text default 'MX', enabled boolean default true);
create table public.products(id uuid primary key default gen_random_uuid(), name text, normalized_name text unique, category text, brand text, gtin text, variant_label text, net_quantity numeric, unit text, pack_count integer, canonical_variant_key text);
create table public.branches(id uuid primary key default gen_random_uuid(), store_id uuid, name text, address text, municipality text, latitude numeric, longitude numeric, geocoding_status text);
create table public.store_products(id uuid primary key default gen_random_uuid(), store_id uuid, product_id uuid, external_name text, store_product_url text, image_url text, presentation text);
create index on public.store_products(product_id);
create table public.price_snapshots(id uuid primary key default gen_random_uuid(), store_product_id uuid, branch_id uuid, price_scope text, price numeric, currency text, available boolean, source text, captured_at timestamptz, external_reference text, raw_payload jsonb);
create index on public.price_snapshots(store_product_id,captured_at desc);
create unique index on public.price_snapshots(store_product_id,captured_at) where branch_id is null;
create table public.product_images(id uuid primary key default gen_random_uuid(), store_product_id uuid, image_url text);
create index on public.product_images(store_product_id);
