create extension if not exists pgcrypto;
create extension if not exists pg_trgm;

create table public.stores (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  country text not null default 'MX',
  enabled boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  normalized_name text not null unique,
  category text,
  created_at timestamptz not null default now()
);

create table public.store_products (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  external_name text not null,
  external_url text,
  image_url text,
  presentation text,
  available boolean not null default true,
  last_seen_at timestamptz not null default now()
);

create table public.price_snapshots (
  id uuid primary key default gen_random_uuid(),
  store_product_id uuid not null references public.store_products(id) on delete cascade,
  price numeric(10, 2) not null check (price >= 0),
  currency text not null default 'MXN',
  available boolean not null default true,
  scraped_at timestamptz not null default now()
);

create unique index store_products_external_url_unique
  on public.store_products (store_id, product_id, external_url)
  where external_url is not null;

create unique index store_products_external_name_unique
  on public.store_products (store_id, product_id, external_name)
  where external_url is null;

create index store_products_store_id_idx on public.store_products (store_id);
create index store_products_product_id_idx on public.store_products (product_id);
create index price_snapshots_latest_idx
  on public.price_snapshots (store_product_id, scraped_at desc);
create index products_normalized_name_trgm_idx
  on public.products using gin (normalized_name gin_trgm_ops);

create view public.latest_prices
with (security_invoker = true)
as
select
  sp.id as store_product_id,
  p.id as product_id,
  p.name as product_name,
  p.normalized_name,
  p.category,
  s.id as store_id,
  s.name as store_name,
  s.slug as store_slug,
  sp.external_name,
  sp.external_url,
  sp.image_url,
  sp.presentation,
  ps.price,
  ps.currency,
  ps.available,
  ps.scraped_at as last_updated_at
from public.store_products sp
join public.stores s on s.id = sp.store_id
join public.products p on p.id = sp.product_id
join lateral (
  select price, currency, available, scraped_at
  from public.price_snapshots
  where store_product_id = sp.id
  order by scraped_at desc
  limit 1
) ps on true
where s.enabled = true;

create view public.compare_prices
with (security_invoker = true)
as
select
  latest_prices.*,
  dense_rank() over (
    partition by normalized_name
    order by price asc
  ) as price_rank
from public.latest_prices
where available = true;

alter table public.stores enable row level security;
alter table public.products enable row level security;
alter table public.store_products enable row level security;
alter table public.price_snapshots enable row level security;

comment on table public.price_snapshots is
  'Histórico de precios recolectados; la API consulta vistas y nunca scrapea en tiempo real.';
