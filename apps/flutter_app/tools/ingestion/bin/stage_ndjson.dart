import 'dart:convert';
import 'dart:io';

const allowedEvidenceKinds = {
  'product_page',
  'store_api',
  'official_feed',
  'sitemap',
  'manual_review',
};

Future<void> main(List<String> args) async {
  final options = StageOptions.parse(args);
  if (options.showHelp) {
    stdout.writeln(StageOptions.helpText);
    return;
  }

  final input = await readNdjson(options.inputPath);
  if (input.inputRecords == 0) {
    throw StateError('No records found in ${options.inputPath}');
  }

  final report = buildPreflightReport(input);
  final reportText = report.toHumanReadable();
  stdout.writeln(reportText);
  if (options.reportOutPath != null) {
    await File(options.reportOutPath!).writeAsString('$reportText\n');
    stderr.writeln('Wrote preflight report: ${options.reportOutPath}');
  }

  if (options.validateOnly) {
    if (report.rejected > 0) {
      exitCode = 2;
    }
    return;
  }

  if (report.rejected > 0 && !options.allowPartial) {
    stderr.writeln(
      'Preflight rejected ${report.rejected} record(s). '
      'No SQL was generated. Fix the input or use --allow-partial explicitly.',
    );
    exitCode = 2;
    return;
  }

  if (report.publishableRecords.isEmpty) {
    stderr.writeln(
      'No publishable records remain after validation and dedupe.',
    );
    exitCode = 2;
    return;
  }

  final preservationErrors = verifySqlJsonPreservation(
    report.publishableRecords,
  );
  if (preservationErrors.isNotEmpty) {
    stderr.writeln(preservationErrors.join('\n'));
    exitCode = 2;
    return;
  }

  final sql = buildStageSql(
    report.publishableRecords,
    runSource: options.runSource,
    inputRecordCount: report.inputRecords,
    acceptedRecordCount: report.accepted,
    rejectedRecordCount: report.rejected,
    duplicateInputCount: report.duplicateInputRecords,
  );
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
      [
        databaseUrl,
        '--set',
        'ON_ERROR_STOP=1',
        '--file',
        sqlPath,
      ],
      runInShell: false);
  stdout.write(result.stdout);
  stderr.write(result.stderr);

  if (result.exitCode != 0) {
    exitCode = result.exitCode;
    return;
  }

  stderr.writeln(
    'Ingestion SQL completed for ${report.publishable} publishable record(s).',
  );
}

Future<List<Map<String, dynamic>>> readRecords(String path) async {
  final result = await readNdjson(path);
  if (result.parseErrors.isNotEmpty) {
    throw FormatException(result.parseErrors.join('\n'));
  }
  return result.records.map((record) => record.value).toList(growable: false);
}

Future<NdjsonInput> readNdjson(String path) async {
  final parsedRecords = <InputRecord>[];
  final parseErrors = <String>[];
  var inputRecords = 0;
  var lineNumber = 0;
  final lines = File(
    path,
  ).openRead().transform(utf8.decoder).transform(const LineSplitter());

  await for (final line in lines) {
    lineNumber++;
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    inputRecords++;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, dynamic>) {
        parseErrors.add('Line $lineNumber is not a JSON object.');
        continue;
      }
      parsedRecords.add(InputRecord(lineNumber: lineNumber, value: decoded));
    } on FormatException catch (error) {
      parseErrors.add('Line $lineNumber has invalid JSON: ${error.message}');
    }
  }

  return NdjsonInput(
    records: parsedRecords,
    parseErrors: parseErrors,
    inputRecords: inputRecords,
  );
}

List<String> validateRecords(List<Map<String, dynamic>> records) {
  final errors = <String>[];
  for (var index = 0; index < records.length; index++) {
    final row = index + 1;
    for (final issue in validateRecord(records[index])) {
      errors.add('Line $row ${issue.message}');
    }
  }
  return errors;
}

List<ValidationIssue> validateRecord(Map<String, dynamic> record) {
  final issues = <ValidationIssue>[];
  const requiredStringFields = [
    'source',
    'store_brand',
    'store_slug',
    'source_product_name',
    'normalized_name',
    'category',
    'presentation',
    'currency',
    'captured_at',
    'observed_at',
    'source_url',
    'evidence_kind',
    'store_product_url',
    'content_hash',
    'external_reference',
    'review_status',
  ];

  for (final field in requiredStringFields) {
    final value = record[field];
    if (value is! String || value.trim().isEmpty) {
      issues.add(
        ValidationIssue(
          code: 'missing_$field',
          message: 'missing string field: $field',
        ),
      );
    }
  }

  final price = record['price'];
  if (price is! num || !price.isFinite || price <= 0) {
    issues.add(
      ValidationIssue(
        code: 'invalid_price',
        message: 'has invalid price: $price',
      ),
    );
  }

  final currency = record['currency'];
  if (currency is String &&
      currency.trim().isNotEmpty &&
      !RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
    issues.add(
      ValidationIssue(
        code: 'invalid_currency',
        message: 'has invalid currency: $currency',
      ),
    );
  }

  final confidenceScore = record['confidence_score'];
  if (confidenceScore is! num ||
      !confidenceScore.isFinite ||
      confidenceScore < 0.70 ||
      confidenceScore > 1) {
    issues.add(
      ValidationIssue(
        code: 'invalid_confidence_score',
        message: 'has invalid publishable confidence_score: $confidenceScore',
      ),
    );
  }

  if (record['is_synthetic'] != false) {
    issues.add(
      const ValidationIssue(
        code: 'synthetic_record',
        message: 'must be real data with is_synthetic=false',
      ),
    );
  }

  if (record['review_status'] != 'accepted') {
    issues.add(
      ValidationIssue(
        code: 'review_not_accepted',
        message: 'must have review_status=accepted',
      ),
    );
  }

  final available = record['available'];
  if (available is! bool) {
    issues.add(
      ValidationIssue(
        code: 'invalid_available',
        message: 'has invalid available value: $available',
      ),
    );
  }

  final hasBranchData = const [
    'branch_external_key',
    'branch_name',
    'branch_address',
    'branch_municipality',
    'branch_state',
    'latitude',
    'longitude',
  ].any((field) {
    final value = record[field];
    return value != null && value.toString().trim().isNotEmpty;
  });
  final priceScope =
      record['price_scope'] ?? (hasBranchData ? 'branch_local' : 'online');
  if (priceScope != 'online' && priceScope != 'branch_local') {
    issues.add(
      ValidationIssue(
        code: 'invalid_price_scope',
        message: 'has invalid price_scope: $priceScope',
      ),
    );
  } else if (priceScope == 'online') {
    for (final field in const [
      'branch_external_key',
      'branch_name',
      'branch_address',
      'branch_municipality',
      'branch_state',
      'latitude',
      'longitude',
    ]) {
      if (record[field] != null && record[field].toString().trim().isNotEmpty) {
        issues.add(
          ValidationIssue(
            code: 'online_has_branch_data',
            message: 'online record must not include $field',
          ),
        );
      }
    }
  } else {
    for (final field in const [
      'branch_external_key',
      'branch_name',
      'branch_address',
      'branch_municipality',
      'branch_state',
    ]) {
      final value = record[field];
      if (value is! String || value.trim().isEmpty) {
        issues.add(
          ValidationIssue(
            code: 'missing_$field',
            message: 'missing string field: $field',
          ),
        );
      }
    }
    final latitude = record['latitude'];
    if (!_isMexicoLatitude(latitude)) {
      issues.add(
        ValidationIssue(
          code: 'invalid_latitude',
          message: 'has invalid Mexico latitude: $latitude',
        ),
      );
    }

    final longitude = record['longitude'];
    if (!_isMexicoLongitude(longitude)) {
      issues.add(
        ValidationIssue(
          code: 'invalid_longitude',
          message: 'has invalid Mexico longitude: $longitude',
        ),
      );
    }
  }

  for (final field in const ['source_url', 'store_product_url']) {
    final value = record[field];
    if (value is String && value.trim().isNotEmpty && !_isHttpUrl(value)) {
      issues.add(
        ValidationIssue(
          code: 'invalid_$field',
          message: '$field must be a valid HTTP(S) URL: $value',
        ),
      );
    }
  }

  final imageUrl = record['image_url'];
  if (imageUrl != null && imageUrl is! String) {
    issues.add(
      ValidationIssue(
        code: 'invalid_image_url',
        message: 'image_url must be null or a valid HTTP(S) URL: $imageUrl',
      ),
    );
  } else if (imageUrl is String &&
      imageUrl.isNotEmpty &&
      !_isHttpUrl(imageUrl)) {
    issues.add(
      ValidationIssue(
        code: 'invalid_image_url',
        message: 'image_url must be null or a valid HTTP(S) URL: $imageUrl',
      ),
    );
  }

  final evidenceKind = record['evidence_kind'];
  if (evidenceKind is String &&
      evidenceKind.trim().isNotEmpty &&
      !allowedEvidenceKinds.contains(evidenceKind)) {
    issues.add(
      ValidationIssue(
        code: 'unknown_evidence',
        message: 'has unknown evidence_kind: $evidenceKind',
      ),
    );
  }

  for (final field in const ['captured_at', 'observed_at']) {
    final value = record[field];
    if (value is String &&
        value.trim().isNotEmpty &&
        !_isTimestampWithTimezone(value)) {
      issues.add(
        ValidationIssue(
          code: 'invalid_$field',
          message: 'has invalid timestamp with timezone in $field: $value',
        ),
      );
    }
  }

  final observed =
      DateTime.tryParse(record['observed_at']?.toString() ?? '')?.toUtc();
  final now = DateTime.now().toUtc();
  if (observed != null &&
      (!observed.isAfter(now.subtract(const Duration(days: 7))) ||
          observed.isAfter(now.add(const Duration(minutes: 5))))) {
    issues.add(const ValidationIssue(
        code: 'observation_not_current',
        message:
            'observed_at must be within the last 7 days and not in the future'));
  }
  if (record['currency'] != 'MXN') {
    issues.add(const ValidationIssue(
        code: 'non_mxn', message: 'currency must be MXN'));
  }

  final rawPayload = record['raw_payload'];
  if (rawPayload is! Map<String, dynamic>) {
    issues.add(
      const ValidationIssue(
        code: 'invalid_raw_payload',
        message: 'must include raw_payload as a JSON object',
      ),
    );
  }

  final validationErrors = record['validation_errors'];
  if (validationErrors != null &&
      (validationErrors is! List || validationErrors.isNotEmpty)) {
    issues.add(
      const ValidationIssue(
        code: 'upstream_validation_errors',
        message: 'must not contain upstream validation_errors',
      ),
    );
  }

  final contentHash = record['content_hash'];
  if (contentHash is String &&
      contentHash.trim().isNotEmpty &&
      !RegExp(r'^[A-Za-z0-9:_-]{8,128}$').hasMatch(contentHash)) {
    issues.add(
      ValidationIssue(
        code: 'invalid_content_hash',
        message: 'has invalid content_hash: $contentHash',
      ),
    );
  }

  if (record['source'] == 'home-depot-mx') {
    if (record['store_slug'] != 'home-depot-mx') {
      issues.add(
        const ValidationIssue(
          code: 'invalid_home_depot_store_slug',
          message: 'must use store_slug=home-depot-mx',
        ),
      );
    }
    final branchKey = record['branch_external_key'];
    if (branchKey is String &&
        branchKey.isNotEmpty &&
        !RegExp(r'^home-depot-mx:[0-9]+$').hasMatch(branchKey)) {
      issues.add(
        ValidationIssue(
          code: 'invalid_home_depot_branch_key',
          message: 'has invalid Home Depot branch_external_key: $branchKey',
        ),
      );
    }
  }

  return issues;
}

bool _isHttpUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

bool _isTimestampWithTimezone(String value) {
  if (!RegExp(r'(Z|[+-][0-9]{2}:[0-9]{2})$').hasMatch(value)) {
    return false;
  }
  return DateTime.tryParse(value) != null;
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
      'SQL JSON preservation check failed: decoded value is not a list.',
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

PreflightReport buildPreflightReport(NdjsonInput input) {
  final accepted = <InputRecord>[];
  final rejected = <RejectedRecord>[];
  final reasons = <String, int>{};

  for (final parseError in input.parseErrors) {
    final code = parseError.contains('not a JSON object')
        ? 'not_json_object'
        : 'invalid_json';
    reasons.update(code, (count) => count + 1, ifAbsent: () => 1);
    rejected.add(
      RejectedRecord(
        lineNumber: _lineNumberFromError(parseError),
        source: '<unparsed>',
        branch: '<unparsed>',
        category: '<unparsed>',
        issues: [ValidationIssue(code: code, message: parseError)],
      ),
    );
  }

  for (final inputRecord in input.records) {
    final record = inputRecord.value;
    final issues = validateRecord(record);
    if (issues.isEmpty) {
      accepted.add(inputRecord);
      continue;
    }

    for (final issue in issues) {
      reasons.update(issue.code, (count) => count + 1, ifAbsent: () => 1);
    }
    rejected.add(
      RejectedRecord(
        lineNumber: inputRecord.lineNumber,
        source: _reportValue(record['source']),
        branch: _reportValue(record['branch_external_key']),
        category: _reportValue(record['category']),
        issues: issues,
      ),
    );
  }

  final publishable = <Map<String, dynamic>>[];
  final seenContentKeys = <String>{};
  var duplicateInputRecords = 0;
  for (final inputRecord in accepted) {
    final record = inputRecord.value;
    final key = '${record['source']}\u0000${record['content_hash']}';
    if (!seenContentKeys.add(key)) {
      duplicateInputRecords++;
      reasons.update(
        'duplicate_source_content_hash',
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      continue;
    }
    publishable.add(record);
  }

  final grouped = <String, PreflightGroup>{};
  for (final inputRecord in input.records) {
    final record = inputRecord.value;
    final key = [
      _reportValue(record['source']),
      _reportValue(record['branch_external_key']),
      _reportValue(record['category']),
    ].join('\u0000');
    final group = grouped.putIfAbsent(
      key,
      () => PreflightGroup(
        source: _reportValue(record['source']),
        branch: _reportValue(record['branch_external_key']),
        category: _reportValue(record['category']),
      ),
    );
    group.inputRecords++;
    if (validateRecord(record).isEmpty) {
      group.accepted++;
    } else {
      group.rejected++;
    }
  }

  return PreflightReport(
    inputRecords: input.inputRecords,
    accepted: accepted.length,
    rejected: rejected.length,
    duplicateInputRecords: duplicateInputRecords,
    publishableRecords: publishable,
    rejectionReasons: reasons,
    rejectedRecords: rejected,
    groups: grouped.values.toList(growable: false)
      ..sort((a, b) {
        final source = a.source.compareTo(b.source);
        if (source != 0) return source;
        final branch = a.branch.compareTo(b.branch);
        if (branch != 0) return branch;
        return a.category.compareTo(b.category);
      }),
  );
}

int _lineNumberFromError(String error) {
  final match = RegExp(r'^Line ([0-9]+)').firstMatch(error);
  return int.tryParse(match?.group(1) ?? '') ?? 0;
}

String _reportValue(Object? value) {
  return value is String && value.isNotEmpty ? value : '<missing>';
}

String buildStageSql(
  List<Map<String, dynamic>> records, {
  required String runSource,
  int? inputRecordCount,
  int? acceptedRecordCount,
  int rejectedRecordCount = 0,
  int duplicateInputCount = 0,
}) {
  final jsonArrayBase64 = encodeRecordsForSqlJson(records);
  final inputCount = inputRecordCount ?? records.length;
  final acceptedCount = acceptedRecordCount ?? records.length;

  return '''
begin;

-- Create the run in a separate statement so the final UPDATE can see it.
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
    $inputCount,
    0,
    jsonb_build_object(
      'tool', 'tools/ingestion/bin/stage_ndjson.dart',
      'input_records', $inputCount,
      'accepted_local', $acceptedCount,
      'rejected_local', $rejectedRecordCount,
      'duplicate_input_records', $duplicateInputCount
    )
  )
returning set_config('tiago.ingestion_run_id', id::text, true);

with scrape_run as (
  select current_setting('tiago.ingestion_run_id')::uuid as id
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
        'price_scope', coalesce(r.payload->>'price_scope', 'branch_local'),
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
    r.payload->>'review_status' as review_status
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
on conflict (source, content_hash)
  where content_hash is not null
do nothing
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
    and payload->>'review_status' = 'accepted'
    and observed_at is not null
    and payload->>'source_url' ~* '^https?://'
    and coalesce((payload->>'confidence_score')::numeric, 0) >= 0.70
    and coalesce(cardinality(
      array(
        select jsonb_array_elements_text(payload->'validation_errors')
        where jsonb_typeof(payload->'validation_errors') = 'array'
      )
    ), 0) = 0
    and (
      (
        normalized_payload->>'price_scope' = 'online'
        and nullif(normalized_payload->>'branch_external_key', '') is null
        and nullif(normalized_payload->>'branch_name', '') is null
        and nullif(normalized_payload->>'branch_address', '') is null
        and nullif(normalized_payload->>'branch_municipality', '') is null
        and nullif(normalized_payload->>'branch_state', '') is null
        and nullif(normalized_payload->>'latitude', '') is null
        and nullif(normalized_payload->>'longitude', '') is null
      )
      or (
        normalized_payload->>'price_scope' = 'branch_local'
        and nullif(normalized_payload->>'branch_external_key', '') is not null
        and nullif(normalized_payload->>'branch_name', '') is not null
        and nullif(normalized_payload->>'branch_address', '') is not null
        and nullif(normalized_payload->>'branch_municipality', '') is not null
        and nullif(normalized_payload->>'branch_state', '') is not null
        and (normalized_payload->>'latitude') ~ '^-?[0-9]+(\\.[0-9]+)?\$'
        and (normalized_payload->>'longitude') ~ '^-?[0-9]+(\\.[0-9]+)?\$'
        and (normalized_payload->>'latitude')::numeric between 14 and 33.5
        and (normalized_payload->>'longitude')::numeric between -119 and -86
      )
    )
),
store_input as (
  select distinct on (normalized_payload->>'store_slug')
    normalized_payload->>'store_brand' as name,
    normalized_payload->>'store_slug' as slug
  from publishable
  order by normalized_payload->>'store_slug', normalized_payload->>'store_brand'
),
stores_upsert as (
  insert into public.stores (name, slug, country, enabled)
  select
    name,
    slug,
    'MX',
    true
  from store_input
  on conflict (slug) do update
    set name = excluded.name,
        enabled = true
  returning id, slug
),
product_input as (
  select distinct on (normalized_payload->>'normalized_name')
    normalized_payload->>'source_product_name' as name,
    normalized_payload->>'normalized_name' as normalized_name,
    normalized_payload->>'category' as category
  from publishable
  order by
    normalized_payload->>'normalized_name',
    normalized_payload->>'source_product_name'
),
products_upsert as (
  insert into public.products (name, normalized_name, category)
  select name, normalized_name, category
  from product_input
  on conflict (normalized_name) do update
    set name = excluded.name,
        category = coalesce(excluded.category, public.products.category)
  returning id, normalized_name
),
branch_input as (
  select distinct on (
    p.source,
    p.normalized_payload->>'branch_external_key'
  )
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
  where p.normalized_payload->>'price_scope' = 'branch_local'
  order by
    p.source,
    p.normalized_payload->>'branch_external_key',
    p.normalized_payload->>'branch_name'
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
store_product_input as (
  select distinct on (
    s.id,
    product.id,
    p.normalized_payload->>'store_product_url'
  )
    s.id,
    product.id,
    p.normalized_payload->>'source_product_name',
    p.normalized_payload->>'store_product_url',
    nullif(p.normalized_payload->>'image_url', ''),
    p.normalized_payload->>'presentation',
    (p.normalized_payload->>'available')::boolean,
    (p.payload->>'observed_at')::timestamptz,
    p.source,
    null::uuid,
    p.normalized_payload->>'store_product_url'
  from publishable p
  join stores_upsert s on s.slug = p.normalized_payload->>'store_slug'
  join products_upsert product
    on product.normalized_name = p.normalized_payload->>'normalized_name'
    left join branches_upsert b
    on b.source = p.source
   and b.external_key = p.normalized_payload->>'branch_external_key'
  order by
    s.id,
    product.id,
    p.normalized_payload->>'store_product_url',
    (p.payload->>'observed_at')::timestamptz desc
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
  select *
  from store_product_input
  on conflict (store_id, product_id, external_url)
    where external_url is not null
  do update
    set external_name = excluded.external_name,
        image_url = excluded.image_url,
        presentation = excluded.presentation,
        available = excluded.available,
        last_seen_at = excluded.last_seen_at,
        source = excluded.source,
        branch_id = null,
        store_product_url = excluded.store_product_url
  returning id, store_id, product_id, external_url
),
snapshot_candidates_raw as (
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
      b.id as branch_id,
      p.normalized_payload->>'price_scope' as price_scope
  from publishable p
  join stores_upsert s on s.slug = p.normalized_payload->>'store_slug'
  join products_upsert product
    on product.normalized_name = p.normalized_payload->>'normalized_name'
  join store_products_upsert sp
    on sp.store_id = s.id
   and sp.product_id = product.id
   and sp.external_url = p.normalized_payload->>'store_product_url'
  left join branches_upsert b
    on b.source = p.source
   and b.external_key = p.normalized_payload->>'branch_external_key'
  where (
    (p.normalized_payload->>'price_scope' = 'online' and b.id is null)
    or (
      p.normalized_payload->>'price_scope' = 'branch_local'
      and b.id is not null
    )
  )
),
snapshot_candidates as (
  select distinct on (store_product_id, branch_id, captured_at)
    store_product_id,
    price,
    currency,
    available,
    source,
    captured_at,
    source_product_name,
    source_store_name,
    source_branch_name,
    external_reference,
    raw_payload,
    branch_id,
    price_scope
  from snapshot_candidates_raw
  order by store_product_id, branch_id, captured_at, external_reference
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
      branch_id,
      price_scope
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
    c.branch_id,
      c.price_scope
  from snapshot_candidates c
  on conflict do nothing
  returning id
),
group_report as (
  select jsonb_agg(
    jsonb_build_object(
      'source', source,
      'branch', branch,
      'category', category,
      'publishable', total
    )
    order by source, branch, category
  ) as value
  from (
    select
      source,
      normalized_payload->>'branch_external_key' as branch,
      normalized_payload->>'category' as category,
      count(*)::integer as total
    from publishable
    group by
      source,
      normalized_payload->>'branch_external_key',
      normalized_payload->>'category'
  ) grouped
),
updated_run as (
  update ingestion.scrape_runs
  set inserted_snapshots = (select count(*) from inserted_snapshots),
      metadata = metadata || jsonb_build_object(
        'input_records', $inputCount,
        'accepted_local', $acceptedCount,
        'rejected_local', $rejectedRecordCount,
        'duplicate_input_records', $duplicateInputCount,
        'new_staging_rows', (select count(*) from staged),
        'reused_staging', (
          select count(*) from staging_for_input where reused_staging
        ),
        'publishable', (select count(*) from publishable),
        'inserted_snapshots', (select count(*) from inserted_snapshots),
        'skipped_existing_snapshots', (
          select count(*) from existing_snapshots
        ),
        'skipped_snapshot_conflicts', (
          (select count(*) from snapshot_candidates) -
          (select count(*) from existing_snapshots) -
          (select count(*) from inserted_snapshots)
        ),
        'by_source_branch_category',
          coalesce((select value from group_report), '[]'::jsonb)
      )
  where id = (select id from scrape_run)
  returning metadata
)
select jsonb_pretty(metadata) as ingestion_report
from updated_run;

commit;
''';
}

String sqlString(String value) {
  return "'${value.replaceAll("'", "''")}'";
}

String encodeRecordsForSqlJson(List<Map<String, dynamic>> records) {
  return base64Encode(utf8.encode(jsonEncode(records)));
}

class NdjsonInput {
  NdjsonInput({
    required this.records,
    required this.parseErrors,
    required this.inputRecords,
  });

  final List<InputRecord> records;
  final List<String> parseErrors;
  final int inputRecords;
}

class InputRecord {
  InputRecord({required this.lineNumber, required this.value});

  final int lineNumber;
  final Map<String, dynamic> value;
}

class ValidationIssue {
  const ValidationIssue({required this.code, required this.message});

  final String code;
  final String message;
}

class RejectedRecord {
  RejectedRecord({
    required this.lineNumber,
    required this.source,
    required this.branch,
    required this.category,
    required this.issues,
  });

  final int lineNumber;
  final String source;
  final String branch;
  final String category;
  final List<ValidationIssue> issues;
}

class PreflightGroup {
  PreflightGroup({
    required this.source,
    required this.branch,
    required this.category,
  });

  final String source;
  final String branch;
  final String category;
  int inputRecords = 0;
  int accepted = 0;
  int rejected = 0;
}

class PreflightReport {
  PreflightReport({
    required this.inputRecords,
    required this.accepted,
    required this.rejected,
    required this.duplicateInputRecords,
    required this.publishableRecords,
    required this.rejectionReasons,
    required this.rejectedRecords,
    required this.groups,
  });

  final int inputRecords;
  final int accepted;
  final int rejected;
  final int duplicateInputRecords;
  final List<Map<String, dynamic>> publishableRecords;
  final Map<String, int> rejectionReasons;
  final List<RejectedRecord> rejectedRecords;
  final List<PreflightGroup> groups;

  int get publishable => publishableRecords.length;

  String toHumanReadable() {
    final buffer = StringBuffer()
      ..writeln('Preflight NDJSON')
      ..writeln('  input_records: $inputRecords')
      ..writeln('  accepted: $accepted')
      ..writeln('  rejected: $rejected')
      ..writeln('  reused_staging: not_checked (requires SQL execution)')
      ..writeln('  publishable: $publishable')
      ..writeln('  inserted_snapshots: not_checked (requires SQL execution)')
      ..writeln(
        '  skipped_existing_snapshots: not_checked (requires SQL execution)',
      )
      ..writeln('  duplicate_input_records: $duplicateInputRecords');

    buffer.writeln('\nBy source / branch / category');
    if (groups.isEmpty) {
      buffer.writeln('  (no parsed records)');
    } else {
      for (final group in groups) {
        buffer.writeln(
          '  ${group.source} | ${group.branch} | ${group.category}: '
          'input=${group.inputRecords}, accepted=${group.accepted}, '
          'rejected=${group.rejected}',
        );
      }
    }

    buffer.writeln('\nRejection reasons');
    if (rejectionReasons.isEmpty) {
      buffer.writeln('  (none)');
    } else {
      final entries = rejectionReasons.entries.toList()
        ..sort((a, b) {
          final count = b.value.compareTo(a.value);
          return count != 0 ? count : a.key.compareTo(b.key);
        });
      for (final entry in entries) {
        buffer.writeln('  ${entry.key}: ${entry.value}');
      }
    }

    if (rejectedRecords.isNotEmpty) {
      buffer.writeln('\nRejected records');
      for (final record in rejectedRecords) {
        buffer.writeln(
          '  line=${record.lineNumber}, source=${record.source}, '
          'branch=${record.branch}, category=${record.category}',
        );
        for (final issue in record.issues) {
          buffer.writeln('    - ${issue.code}: ${issue.message}');
        }
      }
    }

    return buffer.toString().trimRight();
  }
}

class StageOptions {
  StageOptions({
    required this.inputPath,
    required this.runSource,
    this.sqlOutPath,
    this.reportOutPath,
    this.execute = false,
    this.validateOnly = false,
    this.allowPartial = false,
    this.showHelp = false,
  });

  final String inputPath;
  final String runSource;
  final String? sqlOutPath;
  final String? reportOutPath;
  final bool execute;
  final bool validateOnly;
  final bool allowPartial;
  final bool showHelp;

  static StageOptions parse(List<String> args) {
    String? inputPath;
    var runSource = 'manual-ingestion';
    String? sqlOutPath;
    String? reportOutPath;
    var execute = false;
    var validateOnly = false;
    var allowPartial = false;

    for (var index = 0; index < args.length; index++) {
      final arg = args[index];
      if (arg == '--help' || arg == '-h') {
        return StageOptions(
          inputPath: '',
          runSource: runSource,
          sqlOutPath: sqlOutPath,
          reportOutPath: reportOutPath,
          execute: execute,
          validateOnly: validateOnly,
          allowPartial: allowPartial,
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
        case '--report-out':
          reportOutPath = readValue();
        case '--execute':
          execute = true;
        case '--validate-only':
        case '--preflight':
          validateOnly = true;
        case '--allow-partial':
          allowPartial = true;
        default:
          throw ArgumentError('Unknown argument: $arg');
      }
    }

    if (inputPath == null || inputPath.isEmpty) {
      throw ArgumentError('--input is required');
    }
    if (execute && validateOnly) {
      throw ArgumentError(
        '--execute and --validate-only are mutually exclusive',
      );
    }

    return StageOptions(
      inputPath: inputPath,
      runSource: runSource,
      sqlOutPath: sqlOutPath,
      reportOutPath: reportOutPath,
      execute: execute,
      validateOnly: validateOnly,
      allowPartial: allowPartial,
    );
  }

  static const helpText = '''
Usage:
  dart run tools/ingestion/bin/stage_ndjson.dart --input <file.ndjson> [options]

Options:
  --input <path>       NDJSON file generated by a scraper.
  --run-source <name>  scrape_runs.source value. Default: manual-ingestion.
  --sql-out <path>     Write generated SQL to this path.
  --report-out <path>  Also write the human-readable preflight report.
  --validate-only      Validate and report without generating SQL.
  --preflight          Alias for --validate-only.
  --allow-partial      Generate SQL only for accepted records when some reject.
  --execute            Execute SQL with psql using SUPABASE_DB_URL.
  --help               Show this help.
''';
}
