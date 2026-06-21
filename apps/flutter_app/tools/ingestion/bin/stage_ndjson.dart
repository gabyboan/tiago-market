import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final options = StageOptions.parse(args);
  if (options.showHelp) {
    stdout.writeln(StageOptions.helpText);
    return;
  }

  final records = await readRecords(options.inputPath);
  if (records.isEmpty) {
    throw StateError('No records found in ${options.inputPath}');
  }

  final validationErrors = validateRecords(records);
  if (validationErrors.isNotEmpty) {
    stderr.writeln(validationErrors.join('\n'));
    exitCode = 2;
    return;
  }

  final preservationErrors = verifySqlJsonPreservation(records);
  if (preservationErrors.isNotEmpty) {
    stderr.writeln(preservationErrors.join('\n'));
    exitCode = 2;
    return;
  }

  final sql = buildStageSql(records, runSource: options.runSource);
  final sqlPath = options.sqlOutPath ??
      '${Directory.systemTemp.path}/tiago_market_stage_${DateTime.now().microsecondsSinceEpoch}.sql';
  await File(sqlPath).writeAsString(sql);
  stderr.writeln('Wrote staging SQL: $sqlPath');

  if (!options.execute) {
    stderr.writeln('Dry mode only. Re-run with --execute to load Supabase.');
    return;
  }

  final databaseUrl = Platform.environment['SUPABASE_DB_URL'];
  if (databaseUrl == null || databaseUrl.trim().isEmpty) {
    throw StateError(
      'SUPABASE_DB_URL is required when using --execute. '
      'Dry mode wrote SQL to $sqlPath.',
    );
  }

  final result = await Process.run(
    'psql',
    [databaseUrl, '--set', 'ON_ERROR_STOP=1', '--file', sqlPath],
    runInShell: false,
  );
  stdout.write(result.stdout);
  stderr.write(result.stderr);

  if (result.exitCode != 0) {
    exitCode = result.exitCode;
    return;
  }

  stderr.writeln('Loaded ${records.length} record(s) into ingestion staging.');
}

Future<List<Map<String, dynamic>>> readRecords(String path) async {
  final records = <Map<String, dynamic>>[];
  final lines = File(path)
      .openRead()
      .transform(utf8.decoder)
      .transform(const LineSplitter());

  await for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('Each NDJSON line must be a JSON object: $line');
    }
    records.add(decoded);
  }

  return records;
}

List<String> validateRecords(List<Map<String, dynamic>> records) {
  final errors = <String>[];
  for (var index = 0; index < records.length; index++) {
    final record = records[index];
    final row = index + 1;
    final requiredStringFields = [
      'source',
      'store_brand',
      'store_slug',
      'source_product_name',
      'normalized_name',
      'currency',
      'captured_at',
      'observed_at',
      'source_url',
      'evidence_kind',
      'store_product_url',
      'content_hash',
      'branch_external_key',
      'branch_name',
      'branch_address',
      'branch_municipality',
      'branch_state',
      'external_reference',
    ];

    for (final field in requiredStringFields) {
      final value = record[field];
      if (value is! String || value.trim().isEmpty) {
        errors.add('Line $row missing string field: $field');
      }
    }

    final price = record['price'];
    if (price is! num || price <= 0) {
      errors.add('Line $row has invalid price: $price');
    }

    final confidenceScore = record['confidence_score'];
    if (confidenceScore is! num || confidenceScore < 0 || confidenceScore > 1) {
      errors.add('Line $row has invalid confidence_score: $confidenceScore');
    }

    if (record['is_synthetic'] != false) {
      errors.add('Line $row must be real data with is_synthetic=false');
    }

    final available = record['available'];
    if (available is! bool) {
      errors.add('Line $row has invalid available value: $available');
    }

    final latitude = record['latitude'];
    if (!_isMexicoLatitude(latitude)) {
      errors.add('Line $row has invalid Mexico latitude: $latitude');
    }

    final longitude = record['longitude'];
    if (!_isMexicoLongitude(longitude)) {
      errors.add('Line $row has invalid Mexico longitude: $longitude');
    }

    final sourceUrl = record['source_url'];
    if (sourceUrl is String &&
        !(sourceUrl.startsWith('https://') ||
            sourceUrl.startsWith('http://'))) {
      errors.add('Line $row source_url must be HTTP(S): $sourceUrl');
    }
  }
  return errors;
}

const sqlJsonPreservedFields = [
  'source_product_name',
  'normalized_name',
  'branch_address',
  'branch_name',
  'branch_municipality',
  'branch_state',
  'store_product_url',
  'source_url',
];

List<String> verifySqlJsonPreservation(List<Map<String, dynamic>> records) {
  final encoded = encodeRecordsForSqlJson(records);
  final decoded = jsonDecode(utf8.decode(base64Decode(encoded)));
  if (decoded is! List) {
    return const [
      'SQL JSON preservation check failed: decoded value is not a list.'
    ];
  }

  final errors = <String>[];
  for (var index = 0; index < records.length; index++) {
    final original = records[index];
    final roundTripped = decoded[index];
    if (roundTripped is! Map<String, dynamic>) {
      errors.add(
        'SQL JSON preservation check failed on line ${index + 1}: decoded value is not an object.',
      );
      continue;
    }

    for (final field in sqlJsonPreservedFields) {
      final originalValue = original[field];
      final roundTripValue = roundTripped[field];
      if (originalValue != roundTripValue) {
        errors.add(
          'SQL JSON preservation check failed on line ${index + 1} field $field: '
          'expected ${jsonEncode(originalValue)}, got ${jsonEncode(roundTripValue)}.',
        );
      }
    }
  }

  return errors;
}

bool _isMexicoLatitude(Object? value) {
  final parsed = _coordinateValue(value);
  return parsed != null && parsed >= 14 && parsed <= 33.5;
}

bool _isMexicoLongitude(Object? value) {
  final parsed = _coordinateValue(value);
  return parsed != null && parsed >= -119 && parsed <= -86;
}

double? _coordinateValue(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.trim());
  }
  return null;
}

String buildStageSql(
  List<Map<String, dynamic>> records, {
  required String runSource,
}) {
  final jsonArrayBase64 = encodeRecordsForSqlJson(records);
  final fetchedCount = records.length;

  return '''
begin;

with scrape_run as (
  insert into ingestion.scrape_runs (
    source,
    status,
    started_at,
    finished_at,
    fetched_count,
    inserted_snapshots,
    metadata
  ) values (
    ${sqlString(runSource)},
    'success',
    now(),
    now(),
    $fetchedCount,
    0,
    jsonb_build_object(
      'tool', 'tools/ingestion/bin/stage_ndjson.dart',
      'input_records', $fetchedCount
    )
  )
  returning id
),
records as (
  select value as payload
  from jsonb_array_elements(
    convert_from(decode(${sqlString(jsonArrayBase64)}, 'base64'), 'UTF8')::jsonb
  )
),
input_unique as (
  select distinct on (payload->>'source', payload->>'content_hash')
    payload
  from records
  order by payload->>'source', payload->>'content_hash'
),
input_prepared as (
  select
    r.payload,
    r.payload->>'source' as source,
    r.payload->>'content_hash' as content_hash,
    jsonb_build_object(
      'store_brand', r.payload->>'store_brand',
      'store_slug', r.payload->>'store_slug',
      'source_product_name', r.payload->>'source_product_name',
      'normalized_name', r.payload->>'normalized_name',
      'category', r.payload->>'category',
      'presentation', r.payload->>'presentation',
      'price', (r.payload->>'price')::numeric,
      'currency', r.payload->>'currency',
      'available', (r.payload->>'available')::boolean,
      'store_product_url', r.payload->>'store_product_url',
      'image_url', r.payload->>'image_url',
      'external_reference', r.payload->>'external_reference',
      'branch_external_key', r.payload->>'branch_external_key',
      'branch_name', r.payload->>'branch_name',
      'branch_address', r.payload->>'branch_address',
      'branch_municipality', r.payload->>'branch_municipality',
      'branch_state', r.payload->>'branch_state',
      'latitude', r.payload->>'latitude',
      'longitude', r.payload->>'longitude'
    ) as normalized_payload,
    coalesce(
      array(
        select jsonb_array_elements_text(r.payload->'validation_errors')
        where jsonb_typeof(r.payload->'validation_errors') = 'array'
      ),
      '{}'::text[]
    ) as validation_errors,
    r.payload->>'source_url' as source_url,
    coalesce(r.payload->>'evidence_kind', 'unknown') as evidence_kind,
    (r.payload->>'observed_at')::timestamptz as observed_at,
    coalesce((r.payload->>'confidence_score')::numeric, 0) as confidence_score,
    coalesce((r.payload->>'is_synthetic')::boolean, false) as is_synthetic,
    case
      when coalesce(r.payload->>'review_status', 'accepted') = 'rejected'
        then 'rejected'
      else 'accepted'
    end as review_status
  from input_unique r
),
existing_staging as (
  select distinct on (existing.source, existing.content_hash)
    existing.id,
    existing.source,
    existing.content_hash
  from ingestion.source_price_staging existing
  join input_prepared i
    on i.source = existing.source
   and i.content_hash = existing.content_hash
  order by existing.source, existing.content_hash, existing.created_at desc, existing.id desc
),
staged as (
insert into ingestion.source_price_staging (
  run_id,
  source,
  payload,
  normalized_payload,
  validation_errors,
  source_url,
  evidence_kind,
  observed_at,
  confidence_score,
  is_synthetic,
  review_status,
  content_hash
)
select
  scrape_run.id,
  i.source,
  i.payload,
  i.normalized_payload,
  i.validation_errors,
  i.source_url,
  i.evidence_kind,
  i.observed_at,
  i.confidence_score,
  i.is_synthetic,
  i.review_status,
  i.content_hash
from scrape_run
cross join input_prepared i
where not exists (
  select 1
  from existing_staging existing
  where existing.source = i.source
    and existing.content_hash = i.content_hash
)
returning id, source, content_hash
),
staging_for_input as (
  select
    coalesce(staged.id, existing.id) as staging_id,
    i.source,
    i.content_hash,
    i.payload,
    i.normalized_payload,
    i.observed_at,
    existing.id is not null as reused_staging
  from input_prepared i
  left join existing_staging existing
    on existing.source = i.source
   and existing.content_hash = i.content_hash
  left join staged
    on staged.source = i.source
   and staged.content_hash = i.content_hash
),
publishable as (
  select *
  from staging_for_input
  where (payload->>'is_synthetic')::boolean = false
    and coalesce(payload->>'evidence_kind', 'unknown') <> 'unknown'
    and observed_at is not null
    and payload->>'source_url' ~* '^https?://'
    and coalesce((payload->>'confidence_score')::numeric, 0) >= 0.70
    and nullif(normalized_payload->>'branch_external_key', '') is not null
    and nullif(normalized_payload->>'branch_name', '') is not null
    and nullif(normalized_payload->>'branch_address', '') is not null
    and nullif(normalized_payload->>'branch_municipality', '') is not null
    and nullif(normalized_payload->>'branch_state', '') is not null
),
stores_upsert as (
  insert into public.stores (name, slug, country, enabled)
  select distinct
    normalized_payload->>'store_brand',
    normalized_payload->>'store_slug',
    'MX',
    true
  from publishable
  on conflict (slug) do update
    set name = excluded.name,
        enabled = true
  returning id, slug
),
products_upsert as (
  insert into public.products (name, normalized_name, category)
  select distinct
    normalized_payload->>'source_product_name',
    normalized_payload->>'normalized_name',
    normalized_payload->>'category'
  from publishable
  on conflict (normalized_name) do update
    set name = excluded.name,
        category = coalesce(excluded.category, public.products.category)
  returning id, normalized_name
),
branch_input as (
  select distinct
    s.id as store_id,
    p.source,
    p.normalized_payload->>'branch_external_key' as external_key,
    p.normalized_payload->>'branch_name' as name,
    p.normalized_payload->>'branch_address' as address,
    p.normalized_payload->>'branch_municipality' as municipality,
    p.normalized_payload->>'branch_state' as state,
    (p.normalized_payload->>'latitude')::numeric as latitude,
    (p.normalized_payload->>'longitude')::numeric as longitude
  from publishable p
  join stores_upsert s on s.slug = p.normalized_payload->>'store_slug'
),
branches_upsert as (
  insert into public.branches (
    store_id,
    source,
    external_key,
    name,
    address,
    municipality,
    state,
    latitude,
    longitude,
    geocoding_status,
    geocoded_at,
    geocoding_provider,
    geocoding_confidence
  )
  select
    store_id,
    source,
    external_key,
    name,
    address,
    municipality,
    state,
    latitude,
    longitude,
    'manual',
    now(),
    'official_source',
    1
  from branch_input
  on conflict (source, external_key) do update
    set name = excluded.name,
        address = excluded.address,
        municipality = excluded.municipality,
        state = excluded.state,
        latitude = excluded.latitude,
        longitude = excluded.longitude,
        geocoding_status = 'manual',
        geocoded_at = now(),
        geocoding_provider = 'official_source',
        geocoding_confidence = 1,
        updated_at = now()
  returning id, source, external_key
),
store_products_upsert as (
  insert into public.store_products (
    store_id,
    product_id,
    external_name,
    external_url,
    image_url,
    presentation,
    available,
    last_seen_at,
    source,
    branch_id,
    store_product_url
  )
  select
    s.id,
    product.id,
    p.normalized_payload->>'source_product_name',
    p.normalized_payload->>'store_product_url',
    nullif(p.normalized_payload->>'image_url', ''),
    p.normalized_payload->>'presentation',
    (p.normalized_payload->>'available')::boolean,
    (p.payload->>'observed_at')::timestamptz,
    p.source,
    b.id,
    p.normalized_payload->>'store_product_url'
  from publishable p
  join stores_upsert s on s.slug = p.normalized_payload->>'store_slug'
  join products_upsert product
    on product.normalized_name = p.normalized_payload->>'normalized_name'
  join branches_upsert b
    on b.source = p.source
   and b.external_key = p.normalized_payload->>'branch_external_key'
  on conflict (store_id, product_id, external_url)
    where external_url is not null
  do update
    set external_name = excluded.external_name,
        image_url = excluded.image_url,
        presentation = excluded.presentation,
        available = excluded.available,
        last_seen_at = excluded.last_seen_at,
        source = excluded.source,
        branch_id = excluded.branch_id,
        store_product_url = excluded.store_product_url
  returning id, store_id, product_id, external_url
),
snapshot_candidates as (
  select
    sp.id as store_product_id,
    (p.normalized_payload->>'price')::numeric as price,
    p.normalized_payload->>'currency' as currency,
    (p.normalized_payload->>'available')::boolean as available,
    p.source,
    (p.payload->>'captured_at')::timestamptz as captured_at,
    p.normalized_payload->>'source_product_name' as source_product_name,
    p.normalized_payload->>'store_brand' as source_store_name,
    p.normalized_payload->>'branch_name' as source_branch_name,
    p.normalized_payload->>'external_reference' as external_reference,
    p.payload as raw_payload,
    b.id as branch_id
  from publishable p
  join stores_upsert s on s.slug = p.normalized_payload->>'store_slug'
  join products_upsert product
    on product.normalized_name = p.normalized_payload->>'normalized_name'
  join store_products_upsert sp
    on sp.store_id = s.id
   and sp.product_id = product.id
   and sp.external_url = p.normalized_payload->>'store_product_url'
  join branches_upsert b
    on b.source = p.source
   and b.external_key = p.normalized_payload->>'branch_external_key'
  where b.id is not null
),
existing_snapshots as (
  select
    c.store_product_id,
    c.branch_id,
    c.captured_at
  from snapshot_candidates c
  join public.price_snapshots existing
    on existing.store_product_id = c.store_product_id
   and existing.branch_id = c.branch_id
   and existing.captured_at = c.captured_at
),
inserted_snapshots as (
  insert into public.price_snapshots (
    store_product_id,
    price,
    currency,
    available,
    scraped_at,
    source,
    captured_at,
    source_product_name,
    source_store_name,
    source_branch_name,
    external_reference,
    raw_payload,
    branch_id
  )
  select
    c.store_product_id,
    c.price,
    c.currency,
    c.available,
    now(),
    c.source,
    c.captured_at,
    c.source_product_name,
    c.source_store_name,
    c.source_branch_name,
    c.external_reference,
    c.raw_payload,
    c.branch_id
  from snapshot_candidates c
  on conflict (store_product_id, branch_id, captured_at)
    where branch_id is not null
  do nothing
  returning id
)
update ingestion.scrape_runs
set inserted_snapshots = (select count(*) from inserted_snapshots),
    metadata = metadata || jsonb_build_object(
      'input_records',
      (select count(*) from records),
      'new_staging_rows',
      (select count(*) from staged),
      'reused_staging_rows',
      (select count(*) from staging_for_input where reused_staging),
      'eligible_records',
      (select count(*) from publishable),
      'inserted_snapshots',
      (select count(*) from inserted_snapshots),
      'skipped_existing_snapshots',
      (select count(*) from existing_snapshots)
    )
where id = (select id from scrape_run);

commit;
''';
}

String sqlString(String value) {
  return "'${value.replaceAll("'", "''")}'";
}

String encodeRecordsForSqlJson(List<Map<String, dynamic>> records) {
  return base64Encode(utf8.encode(jsonEncode(records)));
}

class StageOptions {
  StageOptions({
    required this.inputPath,
    required this.runSource,
    this.sqlOutPath,
    this.execute = false,
    this.showHelp = false,
  });

  final String inputPath;
  final String runSource;
  final String? sqlOutPath;
  final bool execute;
  final bool showHelp;

  static StageOptions parse(List<String> args) {
    String? inputPath;
    var runSource = 'manual-ingestion';
    String? sqlOutPath;
    var execute = false;

    for (var index = 0; index < args.length; index++) {
      final arg = args[index];
      if (arg == '--help' || arg == '-h') {
        return StageOptions(
          inputPath: '',
          runSource: runSource,
          sqlOutPath: sqlOutPath,
          execute: execute,
          showHelp: true,
        );
      }

      String readValue() {
        if (index + 1 >= args.length) {
          throw ArgumentError('Missing value for $arg');
        }
        index++;
        return args[index];
      }

      switch (arg) {
        case '--input':
          inputPath = readValue();
        case '--run-source':
          runSource = readValue();
        case '--sql-out':
          sqlOutPath = readValue();
        case '--execute':
          execute = true;
        default:
          throw ArgumentError('Unknown argument: $arg');
      }
    }

    if (inputPath == null || inputPath.isEmpty) {
      throw ArgumentError('--input is required');
    }

    return StageOptions(
      inputPath: inputPath,
      runSource: runSource,
      sqlOutPath: sqlOutPath,
      execute: execute,
    );
  }

  static const helpText = '''
Usage:
  dart run tools/ingestion/bin/stage_ndjson.dart --input <file.ndjson> [options]

Options:
  --input <path>       NDJSON file generated by a scraper.
  --run-source <name>  scrape_runs.source value. Default: manual-ingestion.
  --sql-out <path>     Write generated SQL to this path.
  --execute            Execute SQL with psql using SUPABASE_DB_URL.
  --help               Show this help.
''';
}
