alter table public.store_products
  add column source text not null default 'direct';

update public.store_products
set source = 'mock'
where external_url like 'https://example.com/%';

update public.store_products
set source = 'profeco'
where external_url like 'https://qqp.profeco.gob.mx/%';

update public.stores
set enabled = false
where slug = 'mock-market';

create index store_products_source_idx on public.store_products (source);

drop view public.compare_prices;

create or replace view public.latest_prices
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
  ps.scraped_at as last_updated_at,
  sp.source
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

grant select on table public.compare_prices to service_role;
