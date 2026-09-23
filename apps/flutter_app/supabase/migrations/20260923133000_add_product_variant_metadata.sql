-- Additive catalog metadata for structured variants and auditable images.
alter table public.products
  add column if not exists brand text,
  add column if not exists gtin text,
  add column if not exists variant_label text,
  add column if not exists net_quantity numeric,
  add column if not exists unit text,
  add column if not exists pack_count integer,
  add column if not exists canonical_variant_key text;

create index if not exists products_gtin_idx
  on public.products (gtin)
  where gtin is not null and nullif(trim(gtin), '') is not null;

create index if not exists products_canonical_variant_key_idx
  on public.products (canonical_variant_key)
  where canonical_variant_key is not null;

create table if not exists public.product_images (
  id uuid primary key default gen_random_uuid(),
  store_product_id uuid not null references public.store_products(id) on delete cascade,
  image_url text not null,
  canonical_url text,
  image_hash text,
  content_type text,
  source text not null,
  is_primary boolean not null default false,
  validation_status text not null default 'unverified',
  checked_at timestamptz,
  created_at timestamptz not null default now(),
  constraint product_images_validation_status_check check (
    validation_status in ('unverified', 'accepted', 'invalid')
  )
);

create unique index if not exists product_images_store_product_url_unique
  on public.product_images (store_product_id, image_url);

create index if not exists product_images_store_product_idx
  on public.product_images (store_product_id, is_primary desc, checked_at desc);

alter table public.product_images enable row level security;
revoke all on public.product_images from public, anon, authenticated;
grant select, insert, update on public.product_images to service_role;

comment on column public.products.canonical_variant_key is
  'Stable structured identity for a product presentation; text normalization remains as fallback.';
comment on table public.product_images is
  'Auditable source images associated with a store listing; store_products.image_url remains the primary compatibility field.';