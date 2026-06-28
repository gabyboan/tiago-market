import 'dart:async';
import 'dart:convert';
import 'dart:io';

const homeDepotBaseUrl = 'https://www.homedepot.com.mx';
const homeDepotCdnBaseUrl = 'https://cdn.homedepot.com.mx';
const defaultRobotsUrl = '$homeDepotBaseUrl/robots.txt';
const defaultUserAgent =
    'TiagoMarketBot/0.1 (+https://tiago-market.local/contact)';
const defaultLatitude = 19.432608;
const defaultLongitude = -99.133209;
const storeId = '10351';
const catalogId = '10101';
const langId = '-5';
const currency = 'MXN';
const contractId = '4000000000000000003';
const searchProfile = 'HCL_V2_findProductsBySearchTermWithPrice';
const detailProfile = 'HCL_V2_findProductByPartNumber_Details';
const defaultDemoTerms = [
  'pintura',
  'herramientas',
  'escalera',
  'sellador',
  'focos',
  'adhesivo',
];

Future<void> main(List<String> args) async {
  final options = ScraperOptions.parse(args);
  if (options.showHelp) {
    stdout.writeln(ScraperOptions.helpText);
    return;
  }

  final client = HttpClient()
    ..autoUncompress = true
    ..connectionTimeout = options.timeout;
  final preflightRequests = RequestMetrics();

  try {
    final robots = await RobotsRules.fetch(
      client: client,
      robotsUrl: options.robotsUrl,
      userAgent: options.userAgent,
      timeout: options.timeout,
      maxAttempts: options.maxAttempts,
      initialBackoff: options.initialBackoff,
      metrics: preflightRequests,
    );

    final locatorUrl = buildStoreLocatorUrl(
      latitude: options.latitude,
      longitude: options.longitude,
    );
    if (!robots.isAllowed(locatorUrl)) {
      throw StateError('robots.txt does not allow store locator: $locatorUrl');
    }

    final locatorJson = await fetchJsonText(
      client: client,
      url: locatorUrl,
      userAgent: options.userAgent,
      timeout: options.timeout,
      maxAttempts: options.maxAttempts,
      initialBackoff: options.initialBackoff,
      metrics: preflightRequests,
    );
    await Future<void>.delayed(options.delay);

    final locator = parseStoreLocatorBranchesWithDiagnostics(locatorJson);
    for (final rejection in locator.rejectionReasons.entries) {
      stderr.writeln(
        'Store locator rejected ${rejection.value} branch(es): ${rejection.key}',
      );
    }
    final branches = locator.branches
        .where(
          (branch) =>
              options.branchId == null || branch.matchesId(options.branchId!),
        )
        .take(options.branchLimit)
        .toList(growable: false);
    if (branches.isEmpty) {
      throw StateError(
        options.branchId == null
            ? 'No Home Depot branches found near coordinates'
            : 'No Home Depot branch matched --branch ${options.branchId}',
      );
    }

    final outputFile = options.outputPath == null
        ? null
        : File(options.outputPath!).openWrite(mode: FileMode.writeOnly);
    final sink = outputFile ?? stdout;
    final emittedKeys = <String>{};
    final capturedAt = DateTime.now().toUtc();
    final summaries = {
      for (final branch in branches)
        branch.externalKey: BranchScrapeSummary(branch: branch),
    };
    var emitted = 0;

    try {
      for (final branch in branches) {
        final summary = summaries[branch.externalKey]!;
        for (final term in options.terms) {
          final termSummary = summary.forTerm(term);
          if (emitted >= options.limit) {
            termSummary.event('global_limit_before_term');
            break;
          }

          final searchUrl = buildProductSearchUrl(
            physicalStoreId: branch.storeNumber,
            searchTerm: term,
            limit: options.searchLimit,
          );
          if (!robots.isAllowed(searchUrl)) {
            termSummary.event('robots_disallowed_search');
            stderr.writeln(
              '${branch.externalKey} [$term] robots.txt skipped search URL.',
            );
            continue;
          }

          String searchJson;
          try {
            searchJson = await fetchJsonText(
              client: client,
              url: searchUrl,
              userAgent: options.userAgent,
              timeout: options.timeout,
              maxAttempts: options.maxAttempts,
              initialBackoff: options.initialBackoff,
              metrics: termSummary.requests,
            );
          } on Object catch (error) {
            termSummary.error('search_request_failed');
            stderr.writeln(
              '${branch.externalKey} [$term] search failed: $error',
            );
            continue;
          }
          await Future<void>.delayed(options.delay);

          final batch = parseSearchProductsWithDiagnostics(
            searchJson,
            branch: branch,
            sourceUrl: searchUrl,
          );
          termSummary.found += batch.found;
          termSummary.qualified += batch.products.length;
          termSummary.addRejections(batch.rejectionReasons);
          final candidates = batch.products;
          var probedForTerm = 0;

          for (
            var candidateIndex = 0;
            candidateIndex < candidates.length;
            candidateIndex++
          ) {
            final candidate = candidates[candidateIndex];
            if (emitted >= options.limit) {
              termSummary.reject(
                'global_limit',
                candidates.length - candidateIndex,
              );
              break;
            }
            if (probedForTerm >= options.productsPerTerm) {
              termSummary.reject(
                'products_per_term_limit',
                candidates.length - candidateIndex,
              );
              break;
            }
            final dedupeKey = '${branch.externalKey}|${candidate.partNumber}';
            if (!emittedKeys.add(dedupeKey)) {
              termSummary.reject('duplicate_product_across_terms');
              continue;
            }
            probedForTerm++;
            termSummary.probed++;

            final detailUrl = buildProductDetailUrl(
              physicalStoreId: branch.storeNumber,
              partNumber: candidate.partNumber,
            );
            HomeDepotProductEvidence evidence = candidate;
            if (robots.isAllowed(detailUrl)) {
              try {
                final detailJson = await fetchJsonText(
                  client: client,
                  url: detailUrl,
                  userAgent: options.userAgent,
                  timeout: options.timeout,
                  maxAttempts: options.maxAttempts,
                  initialBackoff: options.initialBackoff,
                  metrics: termSummary.requests,
                );
                await Future<void>.delayed(options.delay);
                final detail = parseProductDetailWithDiagnostics(
                  detailJson,
                  branch: branch,
                  sourceUrl: detailUrl,
                );
                if (detail.evidence != null) {
                  evidence = detail.evidence!;
                } else {
                  termSummary.warn('detail_evidence_rejected');
                  stderr.writeln(
                    '${branch.externalKey} [$term] detail evidence rejected '
                    'for ${candidate.partNumber}: ${detail.rejectionReason}',
                  );
                }
              } on Object catch (error) {
                termSummary.warn('detail_request_failed');
                stderr.writeln(
                  '${branch.externalKey} [$term] detail failed for '
                  '${candidate.partNumber}; using validated search evidence: '
                  '$error',
                );
              }
            } else {
              termSummary.warn('robots_disallowed_detail');
            }

            final record = buildStageRecord(
              branch: branch,
              product: evidence,
              searchTerm: term,
              category: categoryForSearchTerm(term),
              capturedAt: capturedAt,
            );
            if (record == null) {
              termSummary.reject(
                evidence.available ? 'invalid_branch_location' : 'out_of_stock',
              );
              continue;
            }
            sink.writeln(jsonEncode(record));
            emitted++;
            termSummary.emitted++;
          }
        }
      }
    } finally {
      if (outputFile != null) {
        await outputFile.flush();
        await outputFile.close();
      }
    }

    stderr.writeln('Home Depot branch summary');
    stderr.writeln(
      'Preflight requests: ${preflightRequests.toHumanReadable()}',
    );
    for (final branch in branches) {
      stderr.writeln(summaries[branch.externalKey]!.toHumanReadable());
    }
    stderr.writeln('Generated $emitted Home Depot staging record(s) total.');
  } finally {
    client.close(force: true);
  }
}

String buildStoreLocatorUrl({
  required double latitude,
  required double longitude,
}) {
  final uri = Uri.https(
    'www.homedepot.com.mx',
    '/wcs/resources/store/$storeId/storelocator/latitude/$latitude/longitude/$longitude',
    {'responseFormat': 'json', 'langId': langId},
  );
  return uri.toString();
}

String buildProductSearchUrl({
  required String physicalStoreId,
  required String searchTerm,
  required int limit,
}) {
  final uri =
      Uri.https('www.homedepot.com.mx', '/search/resources/api/v2/products', {
        'storeId': storeId,
        'searchTerm': searchTerm,
        'catalogId': catalogId,
        'langId': langId,
        'physicalStoreId': physicalStoreId,
        'currency': currency,
        'contractId': contractId,
        'profileName': searchProfile,
        'limit': '$limit',
      });
  return uri.toString();
}

String buildProductDetailUrl({
  required String physicalStoreId,
  required String partNumber,
}) {
  final uri =
      Uri.https('www.homedepot.com.mx', '/search/resources/api/v2/products', {
        'storeId': storeId,
        'partNumber': partNumber,
        'catalogId': catalogId,
        'langId': langId,
        'physicalStoreId': physicalStoreId,
        'currency': currency,
        'contractId': contractId,
        'profileName': detailProfile,
      });
  return uri.toString();
}

Future<String> fetchJsonText({
  required HttpClient client,
  required String url,
  required String userAgent,
  Duration timeout = const Duration(seconds: 20),
  int maxAttempts = 3,
  Duration initialBackoff = const Duration(seconds: 2),
  RequestMetrics? metrics,
}) async {
  metrics?.requests++;
  Object? lastError;
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    metrics?.attempts++;
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(timeout);
      request.headers
        ..set(HttpHeaders.userAgentHeader, userAgent)
        ..set(HttpHeaders.acceptHeader, 'application/json,text/plain,*/*')
        ..set(HttpHeaders.acceptEncodingHeader, 'gzip, deflate');

      final response = await request.close().timeout(timeout);
      final body = await utf8.decodeStream(response).timeout(timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        metrics?.successfulRequests++;
        return body;
      }

      metrics?.recordHttpError(response.statusCode);
      final message =
          'HTTP ${response.statusCode} while fetching $url: ${_bodyExcerpt(body)}';
      if (!_isRetryableStatus(response.statusCode)) {
        throw HttpException(message, uri: Uri.parse(url));
      }
      throw RetryableHttpException(message);
    } on HttpException {
      metrics?.failedRequests++;
      rethrow;
    } on Object catch (error) {
      lastError = error;
      metrics?.recordException(error);
      if (attempt >= maxAttempts || !_isRetryableError(error)) {
        break;
      }
      metrics?.retries++;
      final multiplier = 1 << (attempt - 1);
      final backoff = Duration(
        milliseconds: initialBackoff.inMilliseconds * multiplier,
      );
      stderr.writeln(
        'Request attempt $attempt/$maxAttempts failed for $url: $error. '
        'Retrying in ${backoff.inMilliseconds} ms.',
      );
      await Future<void>.delayed(backoff);
    }
  }

  metrics?.failedRequests++;
  throw StateError(
    'Request failed after $maxAttempts attempt(s) for $url: $lastError',
  );
}

bool _isRetryableStatus(int statusCode) {
  return statusCode == 408 ||
      statusCode == 425 ||
      statusCode == 429 ||
      (statusCode >= 500 && statusCode <= 504);
}

bool _isRetryableError(Object error) {
  return error is TimeoutException ||
      error is SocketException ||
      error is RetryableHttpException;
}

String _bodyExcerpt(String body) {
  final compact = body.trim().replaceAll(RegExp(r'\s+'), ' ');
  return compact.length <= 300 ? compact : '${compact.substring(0, 300)}…';
}

class RetryableHttpException implements Exception {
  RetryableHttpException(this.message);

  final String message;

  @override
  String toString() => message;
}

List<HomeDepotBranch> parseStoreLocatorBranches(String body) {
  return parseStoreLocatorBranchesWithDiagnostics(body).branches;
}

HomeDepotBranchBatch parseStoreLocatorBranchesWithDiagnostics(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Store locator response must be a JSON object');
  }

  final stores = decoded['PhysicalStore'];
  if (stores is! List) {
    return HomeDepotBranchBatch(
      branches: const [],
      rejectionReasons: const {'missing_physical_store_list': 1},
    );
  }

  final branches = <HomeDepotBranch>[];
  final rejectionReasons = <String, int>{};
  for (final rawStore in stores) {
    if (rawStore is! Map<String, dynamic>) {
      rejectionReasons.update(
        'invalid_store_object',
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      continue;
    }
    try {
      final description = _firstMap(rawStore['Description']);
      final displayName =
          _asString(description?['displayStoreName']) ??
          _asString(rawStore['storeName']) ??
          'Sucursal';
      final addressLines = (rawStore['addressLine'] is List)
          ? (rawStore['addressLine'] as List)
                .map(_asString)
                .whereType<String>()
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty)
                .toList()
          : const <String>[];
      final storeNumber = _requiredString(rawStore['storeName'], 'storeName');
      final uniqueId = _requiredString(rawStore['uniqueID'], 'uniqueID');
      final branch = HomeDepotBranch(
        storeNumber: storeNumber,
        uniqueId: uniqueId,
        externalKey: 'home-depot-mx:$storeNumber',
        name: 'The Home Depot $displayName',
        address: addressLines.join(', '),
        municipality: _requiredString(rawStore['city'], 'city'),
        state: _requiredString(
          rawStore['stateOrProvinceName'],
          'stateOrProvinceName',
        ),
        postalCode: _asString(rawStore['postalCode'])?.trim(),
        latitude: _requiredDouble(rawStore['latitude'], 'latitude'),
        longitude: _requiredDouble(rawStore['longitude'], 'longitude'),
        marketId: _attributeValue(rawStore['Attribute'], 'MarketId'),
      );
      if (!branch.hasConfirmedMexicoLocation) {
        throw const FormatException('branch location is not publishable');
      }
      branches.add(branch);
    } on FormatException catch (error) {
      final reason = 'invalid_branch:${error.message}';
      rejectionReasons.update(reason, (count) => count + 1, ifAbsent: () => 1);
    }
  }

  return HomeDepotBranchBatch(
    branches: branches,
    rejectionReasons: rejectionReasons,
  );
}

List<HomeDepotProductEvidence> parseSearchProducts(
  String body, {
  required HomeDepotBranch branch,
  required String sourceUrl,
}) {
  return parseSearchProductsWithDiagnostics(
    body,
    branch: branch,
    sourceUrl: sourceUrl,
  ).products;
}

HomeDepotProductBatch parseSearchProductsWithDiagnostics(
  String body, {
  required HomeDepotBranch branch,
  required String sourceUrl,
}) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException(
      'Product search response must be a JSON object',
    );
  }
  final contents = decoded['contents'];
  if (contents is! List) {
    return HomeDepotProductBatch(
      found: 0,
      products: const [],
      rejectionReasons: const {'missing_contents': 1},
    );
  }

  final products = <HomeDepotProductEvidence>[];
  final rejectionReasons = <String, int>{};
  var found = 0;
  for (final rawProduct in contents.whereType<Map<String, dynamic>>()) {
    final components = rawProduct['components'];
    final items = components is List && components.isNotEmpty
        ? components.whereType<Map<String, dynamic>>()
        : <Map<String, dynamic>>[rawProduct];

    for (final rawItem in items) {
      found++;
      final result = parseProductEvidenceFromJson(
        rawItem,
        branch: branch,
        sourceUrl: sourceUrl,
        fallbackName: _asString(rawProduct['name']),
        fallbackProductUrl: _productUrl(rawProduct['seo']),
        fallbackImageUrl:
            _imageUrl(rawProduct['thumbnailRaw']) ??
            _imageUrl(rawProduct['thumbnail']),
      );
      if (result.evidence != null) {
        products.add(result.evidence!);
      } else {
        final reason = result.rejectionReason ?? 'unknown_product_rejection';
        rejectionReasons.update(
          reason,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }
  }

  return HomeDepotProductBatch(
    found: found,
    products: products,
    rejectionReasons: rejectionReasons,
  );
}

HomeDepotProductEvidence? parseProductDetail(
  String body, {
  required HomeDepotBranch branch,
  required String sourceUrl,
}) {
  return parseProductDetailWithDiagnostics(
    body,
    branch: branch,
    sourceUrl: sourceUrl,
  ).evidence;
}

HomeDepotProductParseResult parseProductDetailWithDiagnostics(
  String body, {
  required HomeDepotBranch branch,
  required String sourceUrl,
}) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException(
      'Product detail response must be a JSON object',
    );
  }
  final contents = decoded['contents'];
  if (contents is! List || contents.isEmpty) {
    return const HomeDepotProductParseResult.rejected(
      'detail_missing_contents',
    );
  }
  final product = contents.whereType<Map<String, dynamic>>().firstOrNull;
  if (product == null) {
    return const HomeDepotProductParseResult.rejected('detail_missing_product');
  }
  return parseProductEvidenceFromJson(
    product,
    branch: branch,
    sourceUrl: sourceUrl,
  );
}

HomeDepotProductEvidence? productEvidenceFromJson(
  Map<String, dynamic> product, {
  required HomeDepotBranch branch,
  required String sourceUrl,
  String? fallbackName,
  String? fallbackProductUrl,
  String? fallbackImageUrl,
}) {
  return parseProductEvidenceFromJson(
    product,
    branch: branch,
    sourceUrl: sourceUrl,
    fallbackName: fallbackName,
    fallbackProductUrl: fallbackProductUrl,
    fallbackImageUrl: fallbackImageUrl,
  ).evidence;
}

HomeDepotProductParseResult parseProductEvidenceFromJson(
  Map<String, dynamic> product, {
  required HomeDepotBranch branch,
  required String sourceUrl,
  String? fallbackName,
  String? fallbackProductUrl,
  String? fallbackImageUrl,
}) {
  final partNumber = _asString(product['partNumber']);
  if (partNumber == null || partNumber.trim().isEmpty) {
    return const HomeDepotProductParseResult.rejected('missing_part_number');
  }

  final uri = Uri.tryParse(sourceUrl);
  if (uri == null ||
      uri.queryParameters['physicalStoreId'] != branch.storeNumber) {
    return const HomeDepotProductParseResult.rejected(
      'physical_store_id_mismatch',
    );
  }

  final branchPriceField = 'x_prices.${branch.storeNumber}.mxn';
  final inventoryField = 'inventories.${branch.uniqueId}.quantity';
  final branchPrice = _asDouble(product[branchPriceField]);
  final offer =
      _priceEntry(product['price'], 'Offer') ??
      _priceEntry(product['price'], 'Display');
  if (branchPrice == null || branchPrice <= 0) {
    return const HomeDepotProductParseResult.rejected(
      'missing_branch_price_field',
    );
  }

  final offerCurrency = _asString(offer?['currency']);
  if (offerCurrency != null && offerCurrency != currency) {
    return HomeDepotProductParseResult.rejected(
      'unexpected_currency:$offerCurrency',
    );
  }

  final inventoryQuantity = _asDouble(product[inventoryField]);
  if (inventoryQuantity == null) {
    return const HomeDepotProductParseResult.rejected(
      'missing_branch_inventory_field',
    );
  }
  final available = inventoryQuantity > 0;

  final productUrl = _productUrl(product['seo']) ?? fallbackProductUrl;
  if (productUrl == null || !_isOfficialHomeDepotUrl(productUrl)) {
    return const HomeDepotProductParseResult.rejected(
      'missing_official_product_url',
    );
  }
  final imageUrl =
      _imageUrl(product['thumbnail']) ??
      _imageUrl(product['thumbnailRaw']) ??
      fallbackImageUrl;
  final name =
      _asString(product['name']) ??
      _asString(product['shortDescription']) ??
      fallbackName;
  if (name == null || name.trim().isEmpty) {
    return const HomeDepotProductParseResult.rejected('missing_product_name');
  }

  return HomeDepotProductParseResult.accepted(
    HomeDepotProductEvidence(
      partNumber: partNumber,
      uniqueId: _asString(product['uniqueID']),
      name: name,
      normalizedName: normalizeName(name),
      brand: _asString(product['manufacturer']),
      price: branchPrice,
      currency: offerCurrency ?? currency,
      available: available,
      inventoryQuantity: inventoryQuantity,
      productUrl: productUrl,
      imageUrl: imageUrl,
      sourceUrl: sourceUrl,
      rawPayload: {
        'part_number': partNumber,
        'unique_id': _asString(product['uniqueID']),
        'price_field': branchPriceField,
        'price_source': 'branch_price_field',
        'branch_price': branchPrice,
        'offer_price': _asString(offer?['value']),
        'offer_currency': offerCurrency,
        'inventory_field': inventoryField,
        'inventory_quantity': inventoryQuantity,
        'parent_catalog_group_id': product['parentCatalogGroupID'],
        'source_fragment': product,
      },
    ),
  );
}

Map<String, Object?>? buildStageRecord({
  required HomeDepotBranch branch,
  required HomeDepotProductEvidence product,
  required String searchTerm,
  String? category,
  DateTime? capturedAt,
}) {
  if (!product.available) {
    return null;
  }
  if (!branch.hasConfirmedMexicoLocation) {
    return null;
  }

  final now = (capturedAt ?? DateTime.now().toUtc()).toUtc().toIso8601String();
  final record = <String, Object?>{
    'source': 'home-depot-mx',
    'store_brand': 'The Home Depot Mexico',
    'store_slug': 'home-depot-mx',
    'source_product_name': product.name,
    'normalized_name': product.normalizedName,
    'category': category ?? categoryForSearchTerm(searchTerm),
    'presentation': inferPresentation(product.name),
    'price': product.price,
    'currency': product.currency,
    'available': product.available,
    'captured_at': now,
    'observed_at': now,
    'source_url': product.sourceUrl,
    'evidence_url': product.sourceUrl,
    'evidence_kind': 'store_api',
    'confidence_score': 0.92,
    'is_synthetic': false,
    'review_status': 'accepted',
    'store_product_url': product.productUrl,
    'image_url': product.imageUrl,
    'external_reference': product.partNumber,
    'branch_external_key': branch.externalKey,
    'branch_name': branch.name,
    'branch_address': branch.address,
    'branch_municipality': branch.municipality,
    'branch_state': branch.state,
    'latitude': branch.latitude,
    'longitude': branch.longitude,
    'raw_payload': {
      'search_term': searchTerm,
      'branch': branch.toJson(),
      'product': product.rawPayload,
    },
  };

  record['content_hash'] = stableHash(
    [
      record['source'],
      record['branch_external_key'],
      record['external_reference'],
      record['price'],
      record['available'],
      record['captured_at'],
    ].join('|'),
  );

  return record;
}

String categoryForSearchTerm(String term) {
  switch (normalizeName(term)) {
    case 'pintura':
      return 'Pintura';
    case 'herramientas':
      return 'Herramientas';
    case 'escalera':
      return 'Escaleras';
    case 'sellador':
      return 'Selladores';
    case 'focos':
      return 'Iluminacion';
    case 'adhesivo':
      return 'Adhesivos';
    default:
      return 'Hogar y ferreteria';
  }
}

bool _isOfficialHomeDepotUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.scheme == 'https' &&
      (uri.host == 'www.homedepot.com.mx' ||
          uri.host.endsWith('.homedepot.com.mx'));
}

Map<String, dynamic>? _firstMap(Object? value) {
  if (value is List) {
    return value.whereType<Map<String, dynamic>>().firstOrNull;
  }
  if (value is Map<String, dynamic>) {
    return value;
  }
  return null;
}

Map<String, dynamic>? _priceEntry(Object? value, String usage) {
  if (value is! List) {
    return null;
  }
  for (final entry in value.whereType<Map<String, dynamic>>()) {
    if (_asString(entry['usage']) == usage) {
      return entry;
    }
  }
  return null;
}

String? _productUrl(Object? seo) {
  if (seo is! Map<String, dynamic>) {
    return null;
  }
  final href = _asString(seo['href']);
  if (href == null || href.trim().isEmpty) {
    return null;
  }
  if (href.startsWith('http://') || href.startsWith('https://')) {
    return href;
  }
  if (href.startsWith('/')) {
    return '$homeDepotBaseUrl$href';
  }
  return '$homeDepotBaseUrl/$href';
}

String? _imageUrl(Object? value) {
  final raw = _asString(value);
  if (raw == null || raw.trim().isEmpty) {
    return null;
  }
  if (raw.startsWith('http://') || raw.startsWith('https://')) {
    return raw;
  }
  if (raw.startsWith('/hclstore/') || raw.startsWith('/productos/')) {
    return '$homeDepotCdnBaseUrl$raw';
  }
  if (raw.startsWith('/')) {
    return '$homeDepotBaseUrl$raw';
  }
  return '$homeDepotCdnBaseUrl/$raw';
}

String? _attributeValue(Object? attributes, String name) {
  if (attributes is! List) {
    return null;
  }
  for (final attribute in attributes.whereType<Map<String, dynamic>>()) {
    if (_asString(attribute['name']) == name) {
      return _asString(attribute['value']);
    }
  }
  return null;
}

String _requiredString(Object? value, String field) {
  final parsed = _asString(value);
  if (parsed == null || parsed.trim().isEmpty) {
    throw FormatException('Missing Home Depot branch field: $field');
  }
  return parsed.trim();
}

double _requiredDouble(Object? value, String field) {
  final parsed = _asDouble(value);
  if (parsed == null) {
    throw FormatException('Missing Home Depot branch coordinate: $field');
  }
  return parsed;
}

String? _asString(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value;
  }
  if (value is num || value is bool) {
    return value.toString();
  }
  return null;
}

double? _asDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return double.tryParse(trimmed);
  }
  return null;
}

String inferPresentation(String name) {
  final pattern = RegExp(
    r'(\d+(?:[.,]\d+)?)\s*(kg|kilos?|g|gr|gramos?|l|lt|litros?|ml|piezas|pieza|pzas|pz|m2|m)\b',
    caseSensitive: false,
  );
  final match = pattern.firstMatch(name);
  if (match != null) {
    final quantity = match.group(1)!.replaceAll(',', '.').trim();
    final unit = canonicalPresentationUnit(match.group(2)!, quantity: quantity);
    return '$quantity $unit';
  }

  return '1 pieza';
}

String canonicalPresentationUnit(String value, {String quantity = '1'}) {
  final normalized = value.toLowerCase();
  final isSinglePiece = double.tryParse(quantity) == 1;

  if (normalized == 'kilo' || normalized == 'kilos') {
    return 'kg';
  }
  if (normalized == 'lt' || normalized == 'litro' || normalized == 'litros') {
    return 'l';
  }
  if (normalized == 'gr' || normalized == 'gramo' || normalized == 'gramos') {
    return 'g';
  }
  if (normalized == 'pz' || normalized == 'pzas' || normalized == 'pieza') {
    return isSinglePiece ? 'pieza' : 'piezas';
  }
  if (normalized == 'piezas') {
    return isSinglePiece ? 'pieza' : 'piezas';
  }
  return normalized;
}

String normalizeName(String value) {
  final lower = value.toLowerCase().trim();
  final withoutAccents = lower
      .replaceAll(RegExp('[áàäâ]'), 'a')
      .replaceAll(RegExp('[éèëê]'), 'e')
      .replaceAll(RegExp('[íìïî]'), 'i')
      .replaceAll(RegExp('[óòöô]'), 'o')
      .replaceAll(RegExp('[úùüû]'), 'u')
      .replaceAll('ñ', 'n');
  return withoutAccents
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String stableHash(String value) {
  final mask = BigInt.parse('ffffffffffffffff', radix: 16);
  final prime = BigInt.parse('100000001b3', radix: 16);
  var hash = BigInt.parse('cbf29ce484222325', radix: 16);

  for (final unit in utf8.encode(value)) {
    hash = (hash ^ BigInt.from(unit)) & mask;
    hash = (hash * prime) & mask;
  }

  return hash.toRadixString(16).padLeft(16, '0');
}

class HomeDepotBranchBatch {
  HomeDepotBranchBatch({
    required this.branches,
    required this.rejectionReasons,
  });

  final List<HomeDepotBranch> branches;
  final Map<String, int> rejectionReasons;
}

class HomeDepotProductBatch {
  HomeDepotProductBatch({
    required this.found,
    required this.products,
    required this.rejectionReasons,
  });

  final int found;
  final List<HomeDepotProductEvidence> products;
  final Map<String, int> rejectionReasons;
}

class HomeDepotProductParseResult {
  const HomeDepotProductParseResult.accepted(this.evidence)
    : rejectionReason = null;

  const HomeDepotProductParseResult.rejected(this.rejectionReason)
    : evidence = null;

  final HomeDepotProductEvidence? evidence;
  final String? rejectionReason;
}

class BranchScrapeSummary {
  BranchScrapeSummary({required this.branch});

  final HomeDepotBranch branch;
  final Map<String, TermScrapeSummary> terms = {};

  TermScrapeSummary forTerm(String term) {
    return terms.putIfAbsent(term, () => TermScrapeSummary(term: term));
  }

  String toHumanReadable() {
    final orderedTerms = terms.values.toList()
      ..sort((a, b) => a.term.compareTo(b.term));
    final found = orderedTerms.fold<int>(
      0,
      (total, summary) => total + summary.found,
    );
    final qualified = orderedTerms.fold<int>(
      0,
      (total, summary) => total + summary.qualified,
    );
    final emitted = orderedTerms.fold<int>(
      0,
      (total, summary) => total + summary.emitted,
    );
    final rejected = orderedTerms.fold<int>(
      0,
      (total, summary) => total + summary.rejected,
    );
    final buffer = StringBuffer()
      ..writeln(
        '  ${branch.externalKey} (${branch.name}): '
        'found=$found, qualified=$qualified, emitted=$emitted, '
        'rejected=$rejected',
      );
    for (final term in orderedTerms) {
      buffer.writeln(term.toHumanReadable(indent: '    '));
    }
    return buffer.toString().trimRight();
  }
}

class TermScrapeSummary {
  TermScrapeSummary({required this.term});

  final String term;
  int found = 0;
  int qualified = 0;
  int probed = 0;
  int emitted = 0;
  final Map<String, int> rejectionReasons = {};
  final Map<String, int> warnings = {};
  final Map<String, int> errors = {};
  final Map<String, int> events = {};
  final RequestMetrics requests = RequestMetrics();

  int get rejected =>
      rejectionReasons.values.fold<int>(0, (total, count) => total + count);

  void reject(String reason, [int count = 1]) {
    _increment(rejectionReasons, reason, count);
  }

  void warn(String reason, [int count = 1]) {
    _increment(warnings, reason, count);
  }

  void error(String reason, [int count = 1]) {
    _increment(errors, reason, count);
  }

  void event(String reason, [int count = 1]) {
    _increment(events, reason, count);
  }

  void addRejections(Map<String, int> values) {
    for (final entry in values.entries) {
      reject(entry.key, entry.value);
    }
  }

  String toHumanReadable({String indent = ''}) {
    final groupedReasons = <String, int>{};
    for (final entry in rejectionReasons.entries) {
      _increment(groupedReasons, rejectionCategory(entry.key), entry.value);
    }
    return '$indent[$term] found=$found, qualified=$qualified, probed=$probed, '
        'emitted=$emitted, rejected=$rejected; '
        'categories=[${_formatCounts(groupedReasons)}]; '
        'reasons=[${_formatCounts(rejectionReasons)}]; '
        'warnings=[${_formatCounts(warnings)}]; '
        'errors=[${_formatCounts(errors)}]; '
        'events=[${_formatCounts(events)}]; '
        'requests={${requests.toHumanReadable()}}';
  }
}

class RequestMetrics {
  int requests = 0;
  int attempts = 0;
  int successfulRequests = 0;
  int failedRequests = 0;
  int retries = 0;
  int timeouts = 0;
  int socketErrors = 0;
  final Map<int, int> httpErrors = {};

  void recordHttpError(int statusCode) {
    httpErrors.update(statusCode, (current) => current + 1, ifAbsent: () => 1);
  }

  void recordException(Object error) {
    if (error is TimeoutException) {
      timeouts++;
    } else if (error is SocketException) {
      socketErrors++;
    }
  }

  String toHumanReadable() {
    final httpText = httpErrors.isEmpty
        ? 'none'
        : (httpErrors.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
              .map((entry) => '${entry.key}=${entry.value}')
              .join(',');
    return 'requests=$requests, attempts=$attempts, '
        'success=$successfulRequests, failed=$failedRequests, '
        'retries=$retries, http=[$httpText], '
        'timeouts=$timeouts, socket_errors=$socketErrors';
  }
}

String rejectionCategory(String reason) {
  if (reason == 'missing_branch_price_field') {
    return 'precio_ausente';
  }
  if (reason == 'missing_branch_inventory_field') {
    return 'stock_invalido';
  }
  if (reason == 'duplicate_product_across_terms') {
    return 'sku_duplicado';
  }
  if (reason == 'global_limit' || reason == 'products_per_term_limit') {
    return 'limite';
  }
  if (reason == 'out_of_stock') {
    return 'filtro_deliberado';
  }
  if (reason.startsWith('detail_missing_') ||
      reason == 'missing_contents' ||
      reason == 'missing_part_number' ||
      reason == 'unknown_product_rejection') {
    return 'parsing';
  }
  if (reason == 'physical_store_id_mismatch' ||
      reason == 'missing_official_product_url' ||
      reason == 'missing_product_name' ||
      reason == 'invalid_branch_location' ||
      reason.startsWith('unexpected_currency:')) {
    return 'evidencia_incompleta';
  }
  return 'otro';
}

void _increment(Map<String, int> values, String key, int count) {
  values.update(key, (current) => current + count, ifAbsent: () => count);
}

String _formatCounts(Map<String, int> values) {
  if (values.isEmpty) {
    return 'none';
  }
  return (values.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
      .map((entry) => '${entry.key}=${entry.value}')
      .join(', ');
}

class HomeDepotBranch {
  HomeDepotBranch({
    required this.storeNumber,
    required this.uniqueId,
    required this.externalKey,
    required this.name,
    required this.address,
    required this.municipality,
    required this.state,
    required this.latitude,
    required this.longitude,
    this.postalCode,
    this.marketId,
  });

  final String storeNumber;
  final String uniqueId;
  final String externalKey;
  final String name;
  final String address;
  final String municipality;
  final String state;
  final String? postalCode;
  final double latitude;
  final double longitude;
  final String? marketId;

  bool get hasConfirmedMexicoLocation {
    return storeNumber.trim().isNotEmpty &&
        uniqueId.trim().isNotEmpty &&
        externalKey.trim().isNotEmpty &&
        name.trim().isNotEmpty &&
        address.trim().isNotEmpty &&
        municipality.trim().isNotEmpty &&
        state.trim().isNotEmpty &&
        latitude >= 14 &&
        latitude <= 33.5 &&
        longitude >= -119 &&
        longitude <= -86;
  }

  bool matchesId(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized == storeNumber.toLowerCase() ||
        normalized == uniqueId.toLowerCase() ||
        normalized == externalKey.toLowerCase();
  }

  Map<String, Object?> toJson() => {
    'store_number': storeNumber,
    'unique_id': uniqueId,
    'external_key': externalKey,
    'name': name,
    'address': address,
    'municipality': municipality,
    'state': state,
    'postal_code': postalCode,
    'latitude': latitude,
    'longitude': longitude,
    'market_id': marketId,
  };
}

class HomeDepotProductEvidence {
  HomeDepotProductEvidence({
    required this.partNumber,
    required this.name,
    required this.normalizedName,
    required this.price,
    required this.currency,
    required this.available,
    required this.productUrl,
    required this.sourceUrl,
    required this.rawPayload,
    this.uniqueId,
    this.brand,
    this.inventoryQuantity,
    this.imageUrl,
  });

  final String partNumber;
  final String? uniqueId;
  final String name;
  final String normalizedName;
  final String? brand;
  final double price;
  final String currency;
  final bool available;
  final double? inventoryQuantity;
  final String productUrl;
  final String? imageUrl;
  final String sourceUrl;
  final Map<String, Object?> rawPayload;

  HomeDepotProductEvidence copyWith({String? sourceUrl}) =>
      HomeDepotProductEvidence(
        partNumber: partNumber,
        uniqueId: uniqueId,
        name: name,
        normalizedName: normalizedName,
        brand: brand,
        price: price,
        currency: currency,
        available: available,
        inventoryQuantity: inventoryQuantity,
        productUrl: productUrl,
        imageUrl: imageUrl,
        sourceUrl: sourceUrl ?? this.sourceUrl,
        rawPayload: rawPayload,
      );
}

class RobotsRules {
  RobotsRules(this.rules);

  final List<RobotsRule> rules;

  static Future<RobotsRules> fetch({
    required HttpClient client,
    required String robotsUrl,
    required String userAgent,
    Duration timeout = const Duration(seconds: 20),
    int maxAttempts = 3,
    Duration initialBackoff = const Duration(seconds: 2),
    RequestMetrics? metrics,
  }) async {
    final body = await fetchJsonText(
      client: client,
      url: robotsUrl,
      userAgent: userAgent,
      timeout: timeout,
      maxAttempts: maxAttempts,
      initialBackoff: initialBackoff,
      metrics: metrics,
    );
    return RobotsRules.parse(body);
  }

  factory RobotsRules.parse(String body) {
    final rules = <RobotsRule>[];
    var appliesToUs = false;

    for (final rawLine in const LineSplitter().convert(body)) {
      final line = rawLine.split('#').first.trim();
      if (line.isEmpty) {
        appliesToUs = false;
        continue;
      }

      final separator = line.indexOf(':');
      if (separator == -1) {
        continue;
      }
      final key = line.substring(0, separator).trim().toLowerCase();
      final value = line.substring(separator + 1).trim();

      if (key == 'user-agent') {
        appliesToUs = value == '*';
      } else if (appliesToUs && (key == 'allow' || key == 'disallow')) {
        if (value.isEmpty) {
          continue;
        }
        rules.add(RobotsRule(pattern: value, allow: key == 'allow'));
      }
    }

    return RobotsRules(rules);
  }

  bool isAllowed(String url) {
    final uri = Uri.parse(url);
    final pathAndQuery = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
    RobotsRule? bestMatch;

    for (final rule in rules) {
      if (!rule.matches(pathAndQuery)) {
        continue;
      }
      if (bestMatch == null ||
          rule.pattern.length > bestMatch.pattern.length ||
          (rule.pattern.length == bestMatch.pattern.length && rule.allow)) {
        bestMatch = rule;
      }
    }

    return bestMatch?.allow ?? true;
  }
}

class RobotsRule {
  RobotsRule({required this.pattern, required this.allow});

  final String pattern;
  final bool allow;

  bool matches(String pathAndQuery) {
    var source = RegExp.escape(
      pattern,
    ).replaceAll(r'\*', '.*').replaceAll(r'\$', r'$');
    if (!source.endsWith(r'$')) {
      source = '$source.*';
    }
    return RegExp('^$source').hasMatch(pathAndQuery);
  }
}

class ScraperOptions {
  ScraperOptions({
    required this.robotsUrl,
    required this.userAgent,
    required this.latitude,
    required this.longitude,
    required this.branchLimit,
    required this.terms,
    required this.limit,
    required this.searchLimit,
    required this.productsPerTerm,
    required this.delay,
    required this.timeout,
    required this.maxAttempts,
    required this.initialBackoff,
    this.branchId,
    this.outputPath,
    this.showHelp = false,
  });

  final String robotsUrl;
  final String userAgent;
  final double latitude;
  final double longitude;
  final int branchLimit;
  final List<String> terms;
  final int limit;
  final int searchLimit;
  final int productsPerTerm;
  final Duration delay;
  final Duration timeout;
  final int maxAttempts;
  final Duration initialBackoff;
  final String? branchId;
  final String? outputPath;
  final bool showHelp;

  static ScraperOptions parse(List<String> args) {
    var robotsUrl = defaultRobotsUrl;
    var userAgent = defaultUserAgent;
    var latitude = defaultLatitude;
    var longitude = defaultLongitude;
    var branchLimit = 3;
    var terms = defaultDemoTerms.toList(growable: false);
    var limit = 90;
    var searchLimit = 8;
    var productsPerTerm = 5;
    var delay = const Duration(milliseconds: 7000);
    var timeout = const Duration(seconds: 20);
    var maxAttempts = 3;
    var initialBackoff = const Duration(seconds: 2);
    String? branchId;
    String? outputPath;
    var showHelp = false;

    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      String nextValue(String name) {
        if (i + 1 >= args.length) {
          throw FormatException('Missing value for $name');
        }
        return args[++i];
      }

      switch (arg) {
        case '--help':
        case '-h':
          showHelp = true;
          break;
        case '--robots-url':
          robotsUrl = nextValue(arg);
          break;
        case '--user-agent':
          userAgent = nextValue(arg);
          break;
        case '--latitude':
          latitude = double.parse(nextValue(arg));
          break;
        case '--longitude':
          longitude = double.parse(nextValue(arg));
          break;
        case '--branch-limit':
          branchLimit = int.parse(nextValue(arg));
          break;
        case '--branch':
          branchId = nextValue(arg).trim();
          break;
        case '--terms':
          terms = nextValue(arg)
              .split(',')
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toList(growable: false);
          break;
        case '--limit':
          limit = int.parse(nextValue(arg));
          break;
        case '--search-limit':
          searchLimit = int.parse(nextValue(arg));
          break;
        case '--products-per-term':
          productsPerTerm = int.parse(nextValue(arg));
          break;
        case '--delay-ms':
          delay = Duration(milliseconds: int.parse(nextValue(arg)));
          break;
        case '--timeout-ms':
          timeout = Duration(milliseconds: int.parse(nextValue(arg)));
          break;
        case '--max-attempts':
          maxAttempts = int.parse(nextValue(arg));
          break;
        case '--backoff-ms':
          initialBackoff = Duration(milliseconds: int.parse(nextValue(arg)));
          break;
        case '--out':
        case '--output':
          outputPath = nextValue(arg);
          break;
        default:
          throw FormatException('Unknown argument: $arg');
      }
    }

    if (branchLimit <= 0 ||
        limit <= 0 ||
        searchLimit <= 0 ||
        productsPerTerm <= 0 ||
        timeout <= Duration.zero ||
        maxAttempts <= 0 ||
        initialBackoff.isNegative) {
      throw const FormatException('Limits must be positive integers');
    }
    if (productsPerTerm > searchLimit) {
      throw const FormatException(
        '--products-per-term cannot exceed --search-limit',
      );
    }
    if (branchLimit > 10 || productsPerTerm > 20 || limit > 500) {
      throw const FormatException(
        'Safety limits exceeded: branch-limit<=10, '
        'products-per-term<=20, limit<=500',
      );
    }
    if (terms.isEmpty) {
      throw const FormatException('At least one search term is required');
    }

    return ScraperOptions(
      robotsUrl: robotsUrl,
      userAgent: userAgent,
      latitude: latitude,
      longitude: longitude,
      branchLimit: branchLimit,
      terms: terms,
      limit: limit,
      searchLimit: searchLimit,
      productsPerTerm: productsPerTerm,
      delay: delay,
      timeout: timeout,
      maxAttempts: maxAttempts,
      initialBackoff: initialBackoff,
      branchId: branchId == null || branchId.isEmpty ? null : branchId,
      outputPath: outputPath,
      showHelp: showHelp,
    );
  }

  static const helpText = '''
Scrapes Home Depot Mexico branch-local product prices into geolocated NDJSON.

Usage:
  dart run tools/ingestion/bin/home_depot_mx_scraper.dart [options]

Options:
  --latitude <value>       Locator latitude. Default: 19.432608
  --longitude <value>      Locator longitude. Default: -99.133209
  --branch <id>            Restrict to a storeName, uniqueID or external key.
  --branch-limit <n>       Nearby branches to use. Default: 3
  --terms <a,b,c>          Search terms. Defaults to the six demo terms.
  --limit <n>              Global emitted record safety cap. Default: 90
  --search-limit <n>       Candidates requested per term. Default: 8
  --products-per-term <n>  Max product details probed per branch/term. Default: 5
  --delay-ms <n>           Delay between requests. Default: 7000
  --timeout-ms <n>         Timeout per request phase. Default: 20000
  --max-attempts <n>       Bounded request attempts. Default: 3
  --backoff-ms <n>         Initial exponential backoff. Default: 2000
  --out, --output <path>   Write NDJSON to file instead of stdout.
  --robots-url <url>       robots.txt URL.
  --user-agent <value>     User-Agent header.
''';
}

extension FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) {
      return null;
    }
    return iterator.current;
  }
}
