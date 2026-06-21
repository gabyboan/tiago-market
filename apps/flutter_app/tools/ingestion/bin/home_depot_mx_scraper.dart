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

Future<void> main(List<String> args) async {
  final options = ScraperOptions.parse(args);
  if (options.showHelp) {
    stdout.writeln(ScraperOptions.helpText);
    return;
  }

  final client = HttpClient()
    ..autoUncompress = true
    ..connectionTimeout = const Duration(seconds: 20);

  try {
    final robots = await RobotsRules.fetch(
      client: client,
      robotsUrl: options.robotsUrl,
      userAgent: options.userAgent,
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
    );
    await Future<void>.delayed(options.delay);

    final locatorBranches = parseStoreLocatorBranches(locatorJson);
    final branches = locatorBranches
        .where((branch) =>
            options.branchId == null || branch.matchesId(options.branchId!))
        .take(options.branchLimit)
        .toList(growable: false);
    if (branches.isEmpty) {
      throw StateError(options.branchId == null
          ? 'No Home Depot branches found near coordinates'
          : 'No Home Depot branch matched --branch ${options.branchId}');
    }

    final outputFile = options.outputPath == null
        ? null
        : File(options.outputPath!).openWrite(mode: FileMode.writeOnly);
    final sink = outputFile ?? stdout;
    final emittedKeys = <String>{};
    var emitted = 0;

    try {
      for (final branch in branches) {
        for (final term in options.terms) {
          if (emitted >= options.limit) {
            break;
          }

          final searchUrl = buildProductSearchUrl(
            physicalStoreId: branch.storeNumber,
            searchTerm: term,
            limit: options.searchLimit,
          );
          if (!robots.isAllowed(searchUrl)) {
            stderr.writeln('robots.txt skipped $searchUrl');
            continue;
          }

          final searchJson = await fetchJsonText(
            client: client,
            url: searchUrl,
            userAgent: options.userAgent,
          );
          await Future<void>.delayed(options.delay);

          final candidates = parseSearchProducts(
            searchJson,
            branch: branch,
            sourceUrl: searchUrl,
          );

          for (final candidate in candidates) {
            if (emitted >= options.limit) {
              break;
            }
            final dedupeKey = '${branch.externalKey}|${candidate.partNumber}';
            if (!emittedKeys.add(dedupeKey)) {
              continue;
            }

            final detailUrl = buildProductDetailUrl(
              physicalStoreId: branch.storeNumber,
              partNumber: candidate.partNumber,
            );
            HomeDepotProductEvidence evidence = candidate;
            if (robots.isAllowed(detailUrl)) {
              final detailJson = await fetchJsonText(
                client: client,
                url: detailUrl,
                userAgent: options.userAgent,
              );
              await Future<void>.delayed(options.delay);
              evidence = parseProductDetail(
                    detailJson,
                    branch: branch,
                    sourceUrl: detailUrl,
                  ) ??
                  candidate.copyWith(sourceUrl: detailUrl);
            } else {
              stderr.writeln('robots.txt skipped $detailUrl');
            }

            final record = buildStageRecord(
              branch: branch,
              product: evidence,
              searchTerm: term,
            );
            if (record == null) {
              continue;
            }
            sink.writeln(jsonEncode(record));
            emitted++;
          }
        }
      }
    } finally {
      if (outputFile != null) {
        await outputFile.flush();
        await outputFile.close();
      }
    }

    stderr.writeln('Generated $emitted Home Depot staging record(s).');
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
    {
      'responseFormat': 'json',
      'langId': langId,
    },
  );
  return uri.toString();
}

String buildProductSearchUrl({
  required String physicalStoreId,
  required String searchTerm,
  required int limit,
}) {
  final uri = Uri.https(
    'www.homedepot.com.mx',
    '/search/resources/api/v2/products',
    {
      'storeId': storeId,
      'searchTerm': searchTerm,
      'catalogId': catalogId,
      'langId': langId,
      'physicalStoreId': physicalStoreId,
      'currency': currency,
      'contractId': contractId,
      'profileName': searchProfile,
      'limit': '$limit',
    },
  );
  return uri.toString();
}

String buildProductDetailUrl({
  required String physicalStoreId,
  required String partNumber,
}) {
  final uri = Uri.https(
    'www.homedepot.com.mx',
    '/search/resources/api/v2/products',
    {
      'storeId': storeId,
      'partNumber': partNumber,
      'catalogId': catalogId,
      'langId': langId,
      'physicalStoreId': physicalStoreId,
      'currency': currency,
      'contractId': contractId,
      'profileName': detailProfile,
    },
  );
  return uri.toString();
}

Future<String> fetchJsonText({
  required HttpClient client,
  required String url,
  required String userAgent,
}) async {
  final request = await client.getUrl(Uri.parse(url));
  request.headers
    ..set(HttpHeaders.userAgentHeader, userAgent)
    ..set(HttpHeaders.acceptHeader, 'application/json,text/plain,*/*')
    ..set(HttpHeaders.acceptEncodingHeader, 'gzip, deflate');

  final response = await request.close();
  final body = await utf8.decodeStream(response);

  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpException(
      'HTTP ${response.statusCode} while fetching $url: ${body.trim()}',
      uri: Uri.parse(url),
    );
  }

  return body;
}

List<HomeDepotBranch> parseStoreLocatorBranches(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Store locator response must be a JSON object');
  }

  final stores = decoded['PhysicalStore'];
  if (stores is! List) {
    return const [];
  }

  return stores.whereType<Map<String, dynamic>>().map((store) {
    final description = _firstMap(store['Description']);
    final displayName = _asString(description?['displayStoreName']) ??
        _asString(store['storeName']) ??
        'Sucursal';
    final addressLines = (store['addressLine'] is List)
        ? (store['addressLine'] as List)
            .map(_asString)
            .whereType<String>()
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList()
        : const <String>[];
    final storeNumber = _requiredString(store['storeName'], 'storeName');
    final uniqueId = _requiredString(store['uniqueID'], 'uniqueID');

    return HomeDepotBranch(
      storeNumber: storeNumber,
      uniqueId: uniqueId,
      externalKey: 'home-depot-mx:$storeNumber',
      name: 'The Home Depot $displayName',
      address: addressLines.join(', '),
      municipality: _requiredString(store['city'], 'city'),
      state: _requiredString(store['stateOrProvinceName'], 'state'),
      postalCode: _asString(store['postalCode'])?.trim(),
      latitude: _requiredDouble(store['latitude'], 'latitude'),
      longitude: _requiredDouble(store['longitude'], 'longitude'),
      marketId: _attributeValue(store['Attribute'], 'MarketId'),
    );
  }).toList(growable: false);
}

List<HomeDepotProductEvidence> parseSearchProducts(
  String body, {
  required HomeDepotBranch branch,
  required String sourceUrl,
}) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException(
        'Product search response must be a JSON object');
  }
  final contents = decoded['contents'];
  if (contents is! List) {
    return const [];
  }

  final products = <HomeDepotProductEvidence>[];
  for (final rawProduct in contents.whereType<Map<String, dynamic>>()) {
    final components = rawProduct['components'];
    final items = components is List && components.isNotEmpty
        ? components.whereType<Map<String, dynamic>>()
        : <Map<String, dynamic>>[rawProduct];

    for (final rawItem in items) {
      final evidence = productEvidenceFromJson(
        rawItem,
        branch: branch,
        sourceUrl: sourceUrl,
        fallbackName: _asString(rawProduct['name']),
        fallbackProductUrl: _productUrl(rawProduct['seo']),
        fallbackImageUrl: _imageUrl(rawProduct['thumbnailRaw']) ??
            _imageUrl(rawProduct['thumbnail']),
      );
      if (evidence != null) {
        products.add(evidence);
      }
    }
  }

  return products;
}

HomeDepotProductEvidence? parseProductDetail(
  String body, {
  required HomeDepotBranch branch,
  required String sourceUrl,
}) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException(
        'Product detail response must be a JSON object');
  }
  final contents = decoded['contents'];
  if (contents is! List || contents.isEmpty) {
    return null;
  }
  final product = contents.whereType<Map<String, dynamic>>().firstOrNull;
  if (product == null) {
    return null;
  }
  return productEvidenceFromJson(
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
  final partNumber = _asString(product['partNumber']);
  if (partNumber == null || partNumber.trim().isEmpty) {
    return null;
  }

  final branchPriceField = 'x_prices.${branch.storeNumber}.mxn';
  final inventoryField = 'inventories.${branch.uniqueId}.quantity';
  final branchPrice = _asDouble(product[branchPriceField]);
  final offer = _priceEntry(product['price'], 'Offer') ??
      _priceEntry(product['price'], 'Display');
  final price = branchPrice ?? _asDouble(offer?['value']);
  if (price == null || price <= 0) {
    return null;
  }

  if (!sourceUrl.contains('physicalStoreId=${branch.storeNumber}')) {
    return null;
  }

  final inventoryQuantity = _asDouble(product[inventoryField]);
  final available = inventoryQuantity == null ? true : inventoryQuantity > 0;

  final productUrl = _productUrl(product['seo']) ?? fallbackProductUrl;
  final imageUrl = _imageUrl(product['thumbnail']) ??
      _imageUrl(product['thumbnailRaw']) ??
      fallbackImageUrl;
  final name = _asString(product['name']) ??
      _asString(product['shortDescription']) ??
      fallbackName;
  if (name == null || name.trim().isEmpty) {
    return null;
  }

  return HomeDepotProductEvidence(
    partNumber: partNumber,
    uniqueId: _asString(product['uniqueID']),
    name: name,
    normalizedName: normalizeName(name),
    brand: _asString(product['manufacturer']),
    price: price,
    currency: _asString(offer?['currency']) ?? currency,
    available: available,
    inventoryQuantity: inventoryQuantity,
    productUrl: productUrl ?? homeDepotBaseUrl,
    imageUrl: imageUrl,
    sourceUrl: sourceUrl,
    rawPayload: {
      'part_number': partNumber,
      'unique_id': _asString(product['uniqueID']),
      'price_field': branchPriceField,
      'price_source': branchPrice == null
          ? 'offer_with_physicalStoreId'
          : 'branch_price_field',
      'branch_price': branchPrice,
      'offer_price': _asString(offer?['value']),
      'inventory_field': inventoryField,
      'inventory_quantity': inventoryQuantity,
      'parent_catalog_group_id': product['parentCatalogGroupID'],
    },
  );
}

Map<String, Object?>? buildStageRecord({
  required HomeDepotBranch branch,
  required HomeDepotProductEvidence product,
  required String searchTerm,
}) {
  if (!product.available) {
    return null;
  }
  if (!branch.hasConfirmedMexicoLocation) {
    return null;
  }

  final now = DateTime.now().toUtc().toIso8601String();
  final record = <String, Object?>{
    'source': 'home-depot-mx',
    'store_brand': 'The Home Depot Mexico',
    'store_slug': 'home-depot-mx',
    'source_product_name': product.name,
    'normalized_name': product.normalizedName,
    'category': 'Hogar y ferreteria',
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

  record['content_hash'] = stableHash([
    record['source'],
    record['branch_external_key'],
    record['external_reference'],
    record['price'],
    record['available'],
  ].join('|'));

  return record;
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
    final unit = canonicalPresentationUnit(
      match.group(2)!,
      quantity: quantity,
    );
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
  }) async {
    final body = await fetchJsonText(
      client: client,
      url: robotsUrl,
      userAgent: userAgent,
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
    var source =
        RegExp.escape(pattern).replaceAll(r'\*', '.*').replaceAll(r'\$', r'$');
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
    required this.delay,
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
  final Duration delay;
  final String? branchId;
  final String? outputPath;
  final bool showHelp;

  static ScraperOptions parse(List<String> args) {
    var robotsUrl = defaultRobotsUrl;
    var userAgent = defaultUserAgent;
    var latitude = defaultLatitude;
    var longitude = defaultLongitude;
    var branchLimit = 1;
    var terms = <String>['pintura'];
    var limit = 5;
    var searchLimit = 5;
    var delay = const Duration(milliseconds: 7000);
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
        case '--delay-ms':
          delay = Duration(milliseconds: int.parse(nextValue(arg)));
          break;
        case '--out':
        case '--output':
          outputPath = nextValue(arg);
          break;
        default:
          throw FormatException('Unknown argument: $arg');
      }
    }

    if (branchLimit <= 0 || limit <= 0 || searchLimit <= 0) {
      throw const FormatException('Limits must be positive integers');
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
      delay: delay,
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
  --branch-limit <n>       Nearby branches to use. Default: 1
  --terms <a,b,c>          Search terms. Default: pintura
  --limit <n>              Max emitted product records. Default: 5
  --search-limit <n>       Product search limit per term. Default: 5
  --delay-ms <n>           Delay between requests. Default: 7000
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
