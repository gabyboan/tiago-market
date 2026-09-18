drop extension if exists "pg_net";

create extension if not exists "pg_trgm" with schema "public";


  create table "public"."branches" (
    "id" uuid not null default gen_random_uuid(),
    "store_id" uuid not null,
    "source" text not null,
    "external_key" text not null,
    "name" text not null,
    "address" text,
    "neighborhood" text,
    "postal_code" text,
    "municipality" text,
    "state" text,
    "city_code" text,
    "city_name" text,
    "latitude" numeric(9,6),
    "longitude" numeric(9,6),
    "geocoding_status" text not null default 'pending'::text,
    "geocoded_at" timestamp with time zone,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now(),
    "geocoding_provider" text,
    "geocoding_query" text,
    "geocoding_confidence" numeric(5,4),
    "geocoding_accuracy" text,
    "geocoding_external_id" text,
    "geocoding_payload" jsonb,
    "geocoding_error" text,
    "geocoding_attempts" integer not null default 0,
    "geocoding_last_attempt_at" timestamp with time zone
      );


alter table "public"."branches" enable row level security;


  create table "public"."price_snapshots" (
    "id" uuid not null default gen_random_uuid(),
    "store_product_id" uuid not null,
    "price" numeric(10,2) not null,
    "currency" text not null default 'MXN'::text,
    "available" boolean not null default true,
    "scraped_at" timestamp with time zone not null default now(),
    "source" text not null,
    "captured_at" timestamp with time zone not null,
    "source_product_name" text not null,
    "source_store_name" text not null,
    "source_branch_name" text,
    "source_city_code" text,
    "source_city_name" text,
    "external_reference" text,
    "raw_payload" jsonb not null default '{}'::jsonb,
    "branch_id" uuid
      );


alter table "public"."price_snapshots" enable row level security;


  create table "public"."products" (
    "id" uuid not null default gen_random_uuid(),
    "name" text not null,
    "normalized_name" text not null,
    "category" text,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."products" enable row level security;


  create table "public"."store_products" (
    "id" uuid not null default gen_random_uuid(),
    "store_id" uuid not null,
    "product_id" uuid not null,
    "external_name" text not null,
    "external_url" text,
    "image_url" text,
    "presentation" text,
    "available" boolean not null default true,
    "last_seen_at" timestamp with time zone not null default now(),
    "source" text not null default 'direct'::text,
    "branch_id" uuid,
    "store_product_url" text
      );


alter table "public"."store_products" enable row level security;


  create table "public"."stores" (
    "id" uuid not null default gen_random_uuid(),
    "name" text not null,
    "slug" text not null,
    "country" text not null default 'MX'::text,
    "enabled" boolean not null default true,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."stores" enable row level security;


  create table "public"."user_feedback" (
    "id" uuid not null default gen_random_uuid(),
    "user_id" uuid,
    "message" text not null,
    "context" jsonb not null default '{}'::jsonb,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."user_feedback" enable row level security;

CREATE INDEX branches_city_code_idx ON public.branches USING btree (city_code);

CREATE INDEX branches_geocoded_idx ON public.branches USING btree (latitude, longitude) WHERE ((latitude IS NOT NULL) AND (longitude IS NOT NULL));

CREATE INDEX branches_pending_geocoding_idx ON public.branches USING btree (updated_at, id) WHERE (geocoding_status = ANY (ARRAY['pending'::text, 'failed'::text]));

CREATE UNIQUE INDEX branches_pkey ON public.branches USING btree (id);

CREATE UNIQUE INDEX branches_source_external_key_key ON public.branches USING btree (source, external_key);

CREATE INDEX branches_store_id_idx ON public.branches USING btree (store_id);

CREATE INDEX price_snapshots_branch_id_idx ON public.price_snapshots USING btree (branch_id);

CREATE INDEX price_snapshots_city_code_idx ON public.price_snapshots USING btree (source_city_code) WHERE (source_city_code IS NOT NULL);

CREATE INDEX price_snapshots_latest_idx ON public.price_snapshots USING btree (store_product_id, scraped_at DESC);

CREATE UNIQUE INDEX price_snapshots_observation_unique ON public.price_snapshots USING btree (store_product_id, captured_at);

CREATE UNIQUE INDEX price_snapshots_pkey ON public.price_snapshots USING btree (id);

CREATE INDEX price_snapshots_source_captured_at_idx ON public.price_snapshots USING btree (source, captured_at DESC);

CREATE UNIQUE INDEX products_normalized_name_key ON public.products USING btree (normalized_name);

CREATE INDEX products_normalized_name_trgm_idx ON public.products USING gin (normalized_name public.gin_trgm_ops);

CREATE UNIQUE INDEX products_pkey ON public.products USING btree (id);

CREATE INDEX store_products_branch_id_idx ON public.store_products USING btree (branch_id);

CREATE UNIQUE INDEX store_products_external_name_unique ON public.store_products USING btree (store_id, product_id, external_name) WHERE (external_url IS NULL);

CREATE UNIQUE INDEX store_products_external_url_unique ON public.store_products USING btree (store_id, product_id, external_url) WHERE (external_url IS NOT NULL);

CREATE UNIQUE INDEX store_products_pkey ON public.store_products USING btree (id);

CREATE INDEX store_products_product_id_idx ON public.store_products USING btree (product_id);

CREATE INDEX store_products_source_idx ON public.store_products USING btree (source);

CREATE INDEX store_products_store_id_idx ON public.store_products USING btree (store_id);

CREATE UNIQUE INDEX stores_pkey ON public.stores USING btree (id);

CREATE UNIQUE INDEX stores_slug_key ON public.stores USING btree (slug);

CREATE UNIQUE INDEX user_feedback_pkey ON public.user_feedback USING btree (id);

alter table "public"."branches" add constraint "branches_pkey" PRIMARY KEY using index "branches_pkey";

alter table "public"."price_snapshots" add constraint "price_snapshots_pkey" PRIMARY KEY using index "price_snapshots_pkey";

alter table "public"."products" add constraint "products_pkey" PRIMARY KEY using index "products_pkey";

alter table "public"."store_products" add constraint "store_products_pkey" PRIMARY KEY using index "store_products_pkey";

alter table "public"."stores" add constraint "stores_pkey" PRIMARY KEY using index "stores_pkey";

alter table "public"."user_feedback" add constraint "user_feedback_pkey" PRIMARY KEY using index "user_feedback_pkey";

alter table "public"."branches" add constraint "branches_geocoding_attempts_check" CHECK ((geocoding_attempts >= 0)) not valid;

alter table "public"."branches" validate constraint "branches_geocoding_attempts_check";

alter table "public"."branches" add constraint "branches_geocoding_confidence_check" CHECK (((geocoding_confidence >= (0)::numeric) AND (geocoding_confidence <= (1)::numeric))) not valid;

alter table "public"."branches" validate constraint "branches_geocoding_confidence_check";

alter table "public"."branches" add constraint "branches_geocoding_status_check" CHECK ((geocoding_status = ANY (ARRAY['pending'::text, 'geocoded'::text, 'review'::text, 'failed'::text, 'manual'::text]))) not valid;

alter table "public"."branches" validate constraint "branches_geocoding_status_check";

alter table "public"."branches" add constraint "branches_latitude_check" CHECK (((latitude >= ('-90'::integer)::numeric) AND (latitude <= (90)::numeric))) not valid;

alter table "public"."branches" validate constraint "branches_latitude_check";

alter table "public"."branches" add constraint "branches_longitude_check" CHECK (((longitude >= ('-180'::integer)::numeric) AND (longitude <= (180)::numeric))) not valid;

alter table "public"."branches" validate constraint "branches_longitude_check";

alter table "public"."branches" add constraint "branches_source_external_key_key" UNIQUE using index "branches_source_external_key_key";

alter table "public"."branches" add constraint "branches_store_id_fkey" FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE not valid;

alter table "public"."branches" validate constraint "branches_store_id_fkey";

alter table "public"."price_snapshots" add constraint "price_snapshots_branch_id_fkey" FOREIGN KEY (branch_id) REFERENCES public.branches(id) ON DELETE SET NULL not valid;

alter table "public"."price_snapshots" validate constraint "price_snapshots_branch_id_fkey";

alter table "public"."price_snapshots" add constraint "price_snapshots_price_check" CHECK ((price >= (0)::numeric)) not valid;

alter table "public"."price_snapshots" validate constraint "price_snapshots_price_check";

alter table "public"."price_snapshots" add constraint "price_snapshots_store_product_id_fkey" FOREIGN KEY (store_product_id) REFERENCES public.store_products(id) ON DELETE CASCADE not valid;

alter table "public"."price_snapshots" validate constraint "price_snapshots_store_product_id_fkey";

alter table "public"."products" add constraint "products_normalized_name_key" UNIQUE using index "products_normalized_name_key";

alter table "public"."store_products" add constraint "store_products_branch_id_fkey" FOREIGN KEY (branch_id) REFERENCES public.branches(id) ON DELETE SET NULL not valid;

alter table "public"."store_products" validate constraint "store_products_branch_id_fkey";

alter table "public"."store_products" add constraint "store_products_product_id_fkey" FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE not valid;

alter table "public"."store_products" validate constraint "store_products_product_id_fkey";

alter table "public"."store_products" add constraint "store_products_store_id_fkey" FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE not valid;

alter table "public"."store_products" validate constraint "store_products_store_id_fkey";

alter table "public"."stores" add constraint "stores_slug_key" UNIQUE using index "stores_slug_key";

alter table "public"."user_feedback" add constraint "user_feedback_message_check" CHECK (((char_length(message) >= 3) AND (char_length(message) <= 2000))) not valid;

alter table "public"."user_feedback" validate constraint "user_feedback_message_check";

alter table "public"."user_feedback" add constraint "user_feedback_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL not valid;

alter table "public"."user_feedback" validate constraint "user_feedback_user_id_fkey";

set check_function_bodies = off;

create or replace view "public"."branch_coverage_summary" as  SELECT (count(*))::integer AS total_normalized_branches,
    (count(*) FILTER (WHERE ((geocoding_status = ANY (ARRAY['geocoded'::text, 'manual'::text])) AND (latitude IS NOT NULL) AND (longitude IS NOT NULL))))::integer AS total_geocoded_branches,
    (count(*) FILTER (WHERE (geocoding_status = 'review'::text)))::integer AS total_review_geocoding,
    (count(*) FILTER (WHERE (geocoding_status = ANY (ARRAY['pending'::text, 'failed'::text]))))::integer AS total_pending_geocoding,
    (count(DISTINCT city_code))::integer AS total_city_codes
   FROM public.branches;


create or replace view "public"."coverage_summary" as  WITH snapshot_totals AS (
         SELECT (count(*))::integer AS total_price_snapshots,
            (count(DISTINCT price_snapshots.source_branch_name))::integer AS total_branches,
            min(price_snapshots.captured_at) AS oldest_snapshot_at,
            max(price_snapshots.captured_at) AS latest_snapshot_at
           FROM public.price_snapshots
        ), snapshot_sources AS (
         SELECT jsonb_object_agg(grouped.source, grouped.total ORDER BY grouped.source) AS "values"
           FROM ( SELECT price_snapshots.source,
                    (count(*))::integer AS total
                   FROM public.price_snapshots
                  GROUP BY price_snapshots.source) grouped
        ), product_sources AS (
         SELECT jsonb_object_agg(grouped.source, grouped.total ORDER BY grouped.source) AS "values"
           FROM ( SELECT store_products.source,
                    (count(DISTINCT store_products.product_id))::integer AS total
                   FROM public.store_products
                  GROUP BY store_products.source) grouped
        ), store_sources AS (
         SELECT jsonb_object_agg(grouped.source, grouped.total ORDER BY grouped.source) AS "values"
           FROM ( SELECT store_products.source,
                    (count(DISTINCT store_products.store_id))::integer AS total
                   FROM public.store_products
                  GROUP BY store_products.source) grouped
        )
 SELECT ( SELECT (count(*))::integer AS count
           FROM public.products) AS total_products,
    ( SELECT (count(*))::integer AS count
           FROM public.stores
          WHERE (stores.enabled = true)) AS total_stores,
    snapshot_totals.total_branches,
    snapshot_totals.total_price_snapshots,
    snapshot_totals.latest_snapshot_at,
    snapshot_totals.oldest_snapshot_at,
    COALESCE(snapshot_sources."values", '{}'::jsonb) AS snapshots_by_source,
    COALESCE(product_sources."values", '{}'::jsonb) AS products_by_source,
    COALESCE(store_sources."values", '{}'::jsonb) AS stores_by_source
   FROM (((snapshot_totals
     CROSS JOIN snapshot_sources)
     CROSS JOIN product_sources)
     CROSS JOIN store_sources);


CREATE OR REPLACE FUNCTION public.distance_km(origin_latitude double precision, origin_longitude double precision, destination_latitude double precision, destination_longitude double precision)
 RETURNS double precision
 LANGUAGE sql
 IMMUTABLE STRICT
 SET search_path TO ''
AS $function$
  select 6371 * 2 * asin(sqrt(
    power(sin(radians(destination_latitude - origin_latitude) / 2), 2) +
    cos(radians(origin_latitude)) *
    cos(radians(destination_latitude)) *
    power(sin(radians(destination_longitude - origin_longitude) / 2), 2)
  ));
$function$
;

create or replace view "public"."latest_prices" as  SELECT sp.id AS store_product_id,
    p.id AS product_id,
    p.name AS product_name,
    p.normalized_name,
    p.category,
    s.id AS store_id,
    ps.source_store_name AS store_name,
    s.slug AS store_slug,
    b.id AS branch_id,
    ps.source_branch_name AS branch_name,
    b.address AS branch_address,
    b.neighborhood AS branch_neighborhood,
    b.postal_code AS branch_postal_code,
    b.municipality AS branch_municipality,
    b.state AS branch_state,
    b.latitude,
    b.longitude,
    ps.source_product_name,
    ps.external_reference AS observation_url,
    sp.store_product_url,
    sp.image_url,
    sp.presentation,
    ps.price,
    ps.currency,
    ps.available,
    ps.source,
    ps.captured_at,
    GREATEST(0, (CURRENT_DATE - (ps.captured_at)::date)) AS days_old,
        CASE
            WHEN ((CURRENT_DATE - (ps.captured_at)::date) < 7) THEN 'fresh'::text
            WHEN ((CURRENT_DATE - (ps.captured_at)::date) <= 21) THEN 'stale'::text
            ELSE 'old'::text
        END AS freshness
   FROM ((((public.store_products sp
     JOIN public.stores s ON ((s.id = sp.store_id)))
     JOIN public.products p ON ((p.id = sp.product_id)))
     JOIN LATERAL ( SELECT price_snapshots.price,
            price_snapshots.currency,
            price_snapshots.available,
            price_snapshots.source,
            price_snapshots.captured_at,
            price_snapshots.source_product_name,
            price_snapshots.source_store_name,
            price_snapshots.source_branch_name,
            price_snapshots.external_reference,
            price_snapshots.branch_id
           FROM public.price_snapshots
          WHERE (price_snapshots.store_product_id = sp.id)
          ORDER BY price_snapshots.captured_at DESC, price_snapshots.id DESC
         LIMIT 1) ps ON (true))
     LEFT JOIN public.branches b ON ((b.id = ps.branch_id)))
  WHERE (s.enabled = true);


CREATE OR REPLACE FUNCTION public.nearby_prices(search_query text, user_latitude double precision, user_longitude double precision, radius_km double precision DEFAULT 10, source_filter text DEFAULT NULL::text, store_filter text DEFAULT NULL::text, only_available boolean DEFAULT true)
 RETURNS TABLE(product_name text, normalized_name text, store_name text, store_slug text, branch_id uuid, branch_name text, branch_address text, branch_municipality text, price numeric, currency text, source text, captured_at timestamp with time zone, freshness text, days_old integer, distance_km double precision)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select
    lp.product_name,
    lp.normalized_name,
    lp.store_name,
    lp.store_slug,
    lp.branch_id,
    lp.branch_name,
    lp.branch_address,
    lp.branch_municipality,
    lp.price,
    lp.currency,
    lp.source,
    lp.captured_at,
    lp.freshness,
    lp.days_old,
    public.distance_km(
      user_latitude,
      user_longitude,
      lp.latitude::double precision,
      lp.longitude::double precision
    ) as distance_km
  from public.latest_prices lp
  join public.branches b on b.id = lp.branch_id
  where lp.normalized_name ilike '%' || search_query || '%'
    and b.geocoding_status in ('geocoded', 'manual')
    and lp.latitude is not null
    and lp.longitude is not null
    and (source_filter is null or lp.source = source_filter)
    and (store_filter is null or lp.store_slug = store_filter)
    and (not only_available or lp.available)
    and public.distance_km(
      user_latitude,
      user_longitude,
      lp.latitude::double precision,
      lp.longitude::double precision
    ) <= radius_km
  order by distance_km asc, lp.price asc;
$function$
;

create or replace view "public"."product_coverage" as  SELECT product_id,
    product_name,
    normalized_name,
    category,
    (count(DISTINCT store_id))::integer AS store_count,
    (count(DISTINCT branch_id))::integer AS listing_count,
    array_agg(DISTINCT source ORDER BY source) AS sources,
    min(captured_at) AS oldest_observation_at,
    max(captured_at) AS last_updated_at
   FROM public.latest_prices
  GROUP BY product_id, product_name, normalized_name, category;


CREATE OR REPLACE FUNCTION public.rls_auto_enable()
 RETURNS event_trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$function$
;

create or replace view "public"."source_stats" as  SELECT source,
    (count(*))::integer AS total_snapshots,
    (count(DISTINCT store_product_id))::integer AS total_listings,
    (count(DISTINCT source_store_name))::integer AS total_stores,
    (count(DISTINCT source_branch_name))::integer AS total_branches,
    min(captured_at) AS oldest_snapshot_at,
    max(captured_at) AS latest_snapshot_at
   FROM public.price_snapshots
  GROUP BY source;


create or replace view "public"."compare_prices" as  SELECT store_product_id,
    product_id,
    product_name,
    normalized_name,
    category,
    store_id,
    store_name,
    store_slug,
    branch_id,
    branch_name,
    branch_address,
    branch_neighborhood,
    branch_postal_code,
    branch_municipality,
    branch_state,
    latitude,
    longitude,
    source_product_name,
    observation_url,
    store_product_url,
    image_url,
    presentation,
    price,
    currency,
    available,
    source,
    captured_at,
    days_old,
    freshness,
    dense_rank() OVER (PARTITION BY normalized_name ORDER BY price) AS price_rank,
    min(price) OVER (PARTITION BY normalized_name) AS best_price
   FROM public.latest_prices
  WHERE ((available = true) AND (freshness <> 'old'::text) AND (source ~~ '%-direct'::text) AND (image_url IS NOT NULL) AND (store_product_url IS NOT NULL));


create or replace view "public"."direct_quality_summary" as  SELECT (count(*))::integer AS total_latest_prices,
    (count(*) FILTER (WHERE (image_url IS NOT NULL)))::integer AS with_image,
    (count(*) FILTER (WHERE (store_product_url IS NOT NULL)))::integer AS with_official_link,
    (count(*) FILTER (WHERE (freshness = 'fresh'::text)))::integer AS fresh_prices,
    (count(*) FILTER (WHERE (freshness = 'stale'::text)))::integer AS stale_prices,
    (count(*) FILTER (WHERE (freshness = 'old'::text)))::integer AS old_prices,
    (count(*) FILTER (WHERE ((price <= (0)::numeric) OR (price > (100000)::numeric))))::integer AS implausible_prices,
    (count(DISTINCT source))::integer AS direct_sources,
    (count(DISTINCT product_id))::integer AS covered_products
   FROM public.latest_prices
  WHERE (source ~~ '%-direct'::text);


grant insert on table "public"."branches" to "service_role";

grant references on table "public"."branches" to "service_role";

grant select on table "public"."branches" to "service_role";

grant trigger on table "public"."branches" to "service_role";

grant truncate on table "public"."branches" to "service_role";

grant update on table "public"."branches" to "service_role";

grant insert on table "public"."price_snapshots" to "service_role";

grant references on table "public"."price_snapshots" to "service_role";

grant select on table "public"."price_snapshots" to "service_role";

grant trigger on table "public"."price_snapshots" to "service_role";

grant truncate on table "public"."price_snapshots" to "service_role";

grant insert on table "public"."products" to "service_role";

grant references on table "public"."products" to "service_role";

grant select on table "public"."products" to "service_role";

grant trigger on table "public"."products" to "service_role";

grant truncate on table "public"."products" to "service_role";

grant update on table "public"."products" to "service_role";

grant insert on table "public"."store_products" to "service_role";

grant references on table "public"."store_products" to "service_role";

grant select on table "public"."store_products" to "service_role";

grant trigger on table "public"."store_products" to "service_role";

grant truncate on table "public"."store_products" to "service_role";

grant update on table "public"."store_products" to "service_role";

grant insert on table "public"."stores" to "service_role";

grant references on table "public"."stores" to "service_role";

grant select on table "public"."stores" to "service_role";

grant trigger on table "public"."stores" to "service_role";

grant truncate on table "public"."stores" to "service_role";

grant update on table "public"."stores" to "service_role";

grant references on table "public"."user_feedback" to "anon";

grant trigger on table "public"."user_feedback" to "anon";

grant truncate on table "public"."user_feedback" to "anon";

grant references on table "public"."user_feedback" to "authenticated";

grant trigger on table "public"."user_feedback" to "authenticated";

grant truncate on table "public"."user_feedback" to "authenticated";

grant insert on table "public"."user_feedback" to "service_role";

grant references on table "public"."user_feedback" to "service_role";

grant trigger on table "public"."user_feedback" to "service_role";

grant truncate on table "public"."user_feedback" to "service_role";


