-- Minimal isolated contract fixture, not a production bootstrap.
create role anon;
create role authenticated;
create role service_role;
create table public.stores(id uuid primary key default gen_random_uuid(), name text not null, slug text unique not null, country text not null default 'MX', enabled boolean not null default true);
create table public.products(id uuid primary key default gen_random_uuid(), name text not null, normalized_name text unique not null, category text, brand text, gtin text, variant_label text, net_quantity numeric, unit text, pack_count integer, canonical_variant_key text);
create table public.branches(id uuid primary key default gen_random_uuid(),store_id uuid references public.stores, name text, address text, municipality text, latitude numeric,longitude numeric,geocoding_status text);
create table public.store_products(id uuid primary key default gen_random_uuid(), store_id uuid references public.stores,product_id uuid references public.products,branch_id uuid references public.branches,external_name text not null,external_url text,store_product_url text,image_url text,presentation text,available boolean default true,source text,last_seen_at timestamptz default now());
create table public.price_snapshots(id uuid primary key default gen_random_uuid(), store_product_id uuid references public.store_products,branch_id uuid references public.branches,price numeric(10,2) check(price>=0),currency text,available boolean,source text,captured_at timestamptz,source_product_name text,source_store_name text,external_reference text,raw_payload jsonb,price_scope text not null default 'branch_local', constraint price_snapshots_scope_check check ((price_scope='online' and branch_id is null) or (price_scope='branch_local' and branch_id is not null)));
create table public.product_images(id uuid primary key default gen_random_uuid(),store_product_id uuid not null references public.store_products on delete cascade,image_url text not null,canonical_url text,image_hash text,content_type text,source text not null,is_primary boolean not null default false,validation_status text not null default 'unverified',checked_at timestamptz,created_at timestamptz not null default now(),constraint product_images_validation_status_check check(validation_status in ('unverified','accepted','invalid')));
create unique index snapshot_observation_unique on public.price_snapshots(store_product_id,coalesce(branch_id,'00000000-0000-0000-0000-000000000000'::uuid),captured_at);
alter table public.stores enable row level security;
alter table public.products enable row level security;
alter table public.branches enable row level security;
alter table public.store_products enable row level security;
alter table public.price_snapshots enable row level security;
create function public.distance_km(lat1 double precision,lon1 double precision,lat2 double precision,lon2 double precision) returns double precision language sql immutable as $$ select 6371*2*asin(sqrt(power(sin(radians(lat2-lat1)/2),2)+cos(radians(lat1))*cos(radians(lat2))*power(sin(radians(lon2-lon1)/2),2))); $$;
