with ranked_snapshots as (
  select
    id,
    row_number() over (
      partition by store_product_id, captured_at
      order by scraped_at desc, id desc
    ) as duplicate_rank
  from public.price_snapshots
)
delete from public.price_snapshots ps
using ranked_snapshots ranked
where ps.id = ranked.id
  and ranked.duplicate_rank > 1;

create unique index price_snapshots_observation_unique
  on public.price_snapshots (store_product_id, captured_at);

comment on index public.price_snapshots_observation_unique is
  'Evita guardar repetidamente la misma observación de una fuente para un listado.';
