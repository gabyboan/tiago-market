begin;

do $$
begin
  if exists (
    select 1
    from ingestion.source_price_staging
    where content_hash is not null
    group by source, content_hash
    having count(*) > 1
  ) then
    raise exception
      'Cannot enforce ingestion staging idempotency: duplicate (source, content_hash) rows exist.';
  end if;
end $$;

create unique index if not exists source_price_staging_source_content_hash_unique
  on ingestion.source_price_staging (source, content_hash)
  where content_hash is not null;

-- The historical identity omitted branch_id and blocks the same product capture
-- timestamp from being stored for more than one physical branch.
drop index if exists public.price_snapshots_observation_unique;

create unique index if not exists price_snapshots_online_observation_unique
  on public.price_snapshots (store_product_id, captured_at)
  where branch_id is null;

create unique index if not exists price_snapshots_store_product_branch_captured_unique
  on public.price_snapshots (store_product_id, branch_id, captured_at)
  where branch_id is not null;

commit;
