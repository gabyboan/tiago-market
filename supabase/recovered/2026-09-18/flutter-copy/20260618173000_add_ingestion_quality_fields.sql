alter table ingestion.source_price_staging
  add column if not exists source_url text,
  add column if not exists evidence_kind text not null default 'unknown',
  add column if not exists observed_at timestamptz,
  add column if not exists confidence_score numeric(3,2) not null default 0,
  add column if not exists is_synthetic boolean not null default false,
  add column if not exists review_status text not null default 'pending',
  add column if not exists reviewed_at timestamptz,
  add column if not exists review_notes text,
  add column if not exists content_hash text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'source_price_staging_evidence_kind_check'
      and conrelid = 'ingestion.source_price_staging'::regclass
  ) then
    alter table ingestion.source_price_staging
      add constraint source_price_staging_evidence_kind_check
      check (evidence_kind in (
        'unknown',
        'product_page',
        'store_api',
        'official_feed',
        'sitemap',
        'manual_review'
      ));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'source_price_staging_confidence_score_check'
      and conrelid = 'ingestion.source_price_staging'::regclass
  ) then
    alter table ingestion.source_price_staging
      add constraint source_price_staging_confidence_score_check
      check (confidence_score >= 0 and confidence_score <= 1);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'source_price_staging_review_status_check'
      and conrelid = 'ingestion.source_price_staging'::regclass
  ) then
    alter table ingestion.source_price_staging
      add constraint source_price_staging_review_status_check
      check (review_status in ('pending', 'accepted', 'rejected'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'source_price_staging_accepted_real_evidence_check'
      and conrelid = 'ingestion.source_price_staging'::regclass
  ) then
    alter table ingestion.source_price_staging
      add constraint source_price_staging_accepted_real_evidence_check
      check (
        review_status <> 'accepted'
        or (
          is_synthetic = false
          and evidence_kind <> 'unknown'
          and observed_at is not null
          and source_url is not null
          and source_url ~* '^https?://'
          and confidence_score >= 0.70
          and coalesce(cardinality(validation_errors), 0) = 0
        )
      );
  end if;
end $$;

create index if not exists source_price_staging_source_created_at_idx
  on ingestion.source_price_staging (source, created_at desc);

create index if not exists source_price_staging_review_status_idx
  on ingestion.source_price_staging (review_status);

create index if not exists source_price_staging_content_hash_idx
  on ingestion.source_price_staging (source, content_hash)
  where content_hash is not null;

create or replace view ingestion.publishable_source_prices as
select *
from ingestion.source_price_staging
where review_status = 'accepted'
  and is_synthetic = false
  and evidence_kind <> 'unknown'
  and observed_at is not null
  and source_url is not null
  and source_url ~* '^https?://'
  and confidence_score >= 0.70
  and coalesce(cardinality(validation_errors), 0) = 0;

revoke all on ingestion.publishable_source_prices from anon, authenticated;
grant all on ingestion.publishable_source_prices to service_role;
