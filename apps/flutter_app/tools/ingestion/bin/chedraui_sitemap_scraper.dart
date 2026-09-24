import 'dart:async';
import 'dart:convert';
import 'dart:io';

const defaultSitemapUrl = 'https://www.chedraui.com.mx/sitemap/product-0.xml';
const defaultRobotsUrl = 'https://www.chedraui.com.mx/robots.txt';
const defaultUserAgent =
    'TiagoMarketBot/0.1 (+https://tiago-market.local/contact)';

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

    final sitemapUrls = options.urlsPath == null
        ? await discoverProductUrls(
            client: client,
            sitemapUrl: options.sitemapUrl,
            userAgent: options.userAgent,
            limit: options.limit,
            robots: robots,
          )
        : readProductUrls(options.urlsPath!).take(options.limit).toList();

    final evidence = options.evidenceDirectory == null
        ? null
        : Directory(options.evidenceDirectory!);
    if (evidence != null) {
      if (evidence.existsSync() ||
          (options.outputPath != null &&
              File(options.outputPath!).existsSync())) {
        throw StateError(
            'Use new output/evidence paths; captures are immutable.');
      }
      await evidence.create(recursive: true);
    }

    final outputFile = options.outputPath == null
        ? null
        : File(options.outputPath!).openWrite(mode: FileMode.writeOnly);
    final sink = outputFile ?? stdout;
    var emitted = 0;
    final rejected = <Map<String, String>>[];
    var attempted = 0;

    try {
      for (final productUrl in sitemapUrls) {
        if (!robots.isAllowed(productUrl)) {
          stderr.writeln('robots.txt skipped $productUrl');
          rejected.add({
            'url': productUrl,
            'reason': 'robots.txt disallows the product URL',
          });
          continue;
        }

        await Future<void>.delayed(options.delay);
        final page = await fetchText(
          client: client,
          url: productUrl,
          userAgent: options.userAgent,
        );
        attempted++;
        final observedAt = DateTime.now().toUtc();
        final receipt = {
          'url': productUrl,
          'observed_at': observedAt.toIso8601String(),
          'body_hash_fnv1a64': stableHash(page),
        };
        if (evidence != null) {
          await File('${evidence.path}/$attempted.html').writeAsString(page);
          await File('${evidence.path}/$attempted.json')
              .writeAsString(jsonEncode(receipt));
        }
        final record = parseChedrauiProductPage(
          productUrl: productUrl,
          html: page,
          observedAt: observedAt,
        );

        if (record == null) {
          stderr.writeln('No publishable price evidence found at $productUrl');
          rejected.add({
            'url': productUrl,
            'reason': 'SKU-bound product evidence is missing or changed',
          });
        } else {
          (record['raw_payload'] as Map)['http_receipt'] = receipt;
          sink.writeln(jsonEncode(record));
          emitted++;
        }

        if (emitted >= options.limit) {
          break;
        }
      }
    } finally {
      if (outputFile != null) {
        await outputFile.flush();
        await outputFile.close();
      }
      if (evidence != null) {
        await File('${evidence.path}/report.json').writeAsString(jsonEncode({
          'attempted': attempted,
          'accepted': emitted,
          'rejected': rejected,
          'complete': attempted == sitemapUrls.length && rejected.isEmpty,
        }));
      }
    }

    stderr.writeln('Generated $emitted Chedraui staging record(s).');
    if (rejected.isNotEmpty || emitted == 0) exitCode = 2;
  } finally {
    client.close(force: true);
  }
}

List<String> readProductUrls(String path) {
  final value = jsonDecode(File(path).readAsStringSync());
  if (value is! List ||
      value.isEmpty ||
      value.any((url) => url is! String || !_looksLikeProductUrl(url))) {
    throw FormatException(
        'Expected a nonempty array of official Chedraui product URLs');
  }
  return value.cast<String>().toSet().toList();
}

Future<List<String>> discoverProductUrls({
  required HttpClient client,
  required String sitemapUrl,
  required String userAgent,
  required int limit,
  required RobotsRules robots,
}) async {
  if (!robots.isAllowed(sitemapUrl)) {
    throw StateError('robots.txt does not allow sitemap URL: $sitemapUrl');
  }

  final xml = await fetchText(
    client: client,
    url: sitemapUrl,
    userAgent: userAgent,
  );
  final locs = extractXmlLocs(xml);

  if (xml.contains('<sitemapindex')) {
    final productSitemaps = locs
        .where((url) => url.contains('/sitemap/product-'))
        .where(robots.isAllowed)
        .toList();
    final urls = <String>[];

    for (final productSitemap in productSitemaps) {
      final childXml = await fetchText(
        client: client,
        url: productSitemap,
        userAgent: userAgent,
      );
      urls.addAll(extractXmlLocs(childXml).where(_looksLikeProductUrl));
      if (urls.length >= limit) {
        break;
      }
    }

    return urls.take(limit).toList();
  }

  return locs.where(_looksLikeProductUrl).take(limit).toList();
}

Future<String> fetchText({
  required HttpClient client,
  required String url,
  required String userAgent,
}) async {
  final request = await client.getUrl(Uri.parse(url));
  request.followRedirects = false;
  request.headers
    ..set(HttpHeaders.userAgentHeader, userAgent)
    ..set(HttpHeaders.acceptHeader, 'text/html,application/xml;q=0.9,*/*;q=0.8')
    ..set(HttpHeaders.acceptEncodingHeader, 'gzip, deflate');

  final response = await request.close().timeout(const Duration(seconds: 30));
  final body =
      await utf8.decodeStream(response).timeout(const Duration(seconds: 30));

  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpException(
      'HTTP ${response.statusCode} while fetching $url: ${body.trim()}',
      uri: Uri.parse(url),
    );
  }

  return body;
}

List<String> extractXmlLocs(String xml) {
  final locPattern = RegExp(r'<loc>\s*([^<]+?)\s*</loc>', caseSensitive: false);
  return locPattern
      .allMatches(xml)
      .map((match) => htmlEntityDecode(match.group(1)!.trim()))
      .toList();
}

Map<String, Object?>? parseChedrauiProductPage({
  required String productUrl,
  required String html,
  DateTime? observedAt,
}) {
  final productId = productUrlId(productUrl);
  if (productId == null || !_looksLikeProductUrl(productUrl)) {
    return null;
  }
  final products = <Map<String, dynamic>>[];
  for (final script in RegExp(
    r'''<script\b[^>]*type=["']application/ld\+json["'][^>]*>(.*?)</script>''',
    caseSensitive: false,
    dotAll: true,
  ).allMatches(html)) {
    try {
      products.addAll(_jsonObjects(jsonDecode(script.group(1)!)).where((node) =>
          node['@type'] == 'Product' &&
          node['@id'] == productUrl &&
          node['mpn']?.toString() == productId));
    } on FormatException {
      return null;
    }
  }
  if (products.length != 1) return null;
  final product = products.single;
  final offers = _jsonObjects(product['offers'])
      .where((node) => node['@type'] == 'Offer')
      .toList();
  if (offers.length != 1) return null;
  final offer = offers.single;
  final seller = offer['seller'];
  if (offer['sku'] != product['sku'] ||
      int.tryParse(product['sku']?.toString() ?? '') !=
          int.tryParse(productId) ||
      seller is! Map ||
      seller['name'] != 'Chedraui' ||
      offer['priceCurrency'] != 'MXN') {
    return null;
  }
  final price = double.tryParse(offer['price']?.toString() ?? '');
  final name = product['name'];
  final available = switch (offer['availability']) {
    'http://schema.org/InStock' || 'https://schema.org/InStock' => true,
    'http://schema.org/OutOfStock' || 'https://schema.org/OutOfStock' => false,
    _ => null,
  };
  if (name is! String ||
      name.trim().isEmpty ||
      price == null ||
      !price.isFinite ||
      price <= 0 ||
      available == null) {
    return null;
  }
  final observation = (observedAt ?? DateTime.now()).toUtc();
  final validUntil = offer['priceValidUntil'];
  if (validUntil != null) {
    final expiry = DateTime.tryParse(validUntil.toString());
    if (expiry == null || !expiry.toUtc().isAfter(observation)) return null;
  }
  // Missing quantities and ambiguous multipacks require review.
  if (!RegExp(r'\d+(?:[.,]\d+)?\s*(?:kg|g|gr|l|lt|ml|piezas?)\b',
              caseSensitive: false)
          .hasMatch(name) ||
      RegExp(r'\b(?:pack|paquete|piezas?\s+de)\b|\d+\s*x\s*\d+',
              caseSensitive: false)
          .hasMatch(name)) {
    return null;
  }
  final image = product['image'];
  final imageUri = image is String ? Uri.tryParse(image) : null;
  final imageUrl = imageUri?.scheme == 'https' &&
          imageUri?.host == 'chedrauimx.vtexassets.com'
      ? image
      : null;
  final now = observation.toIso8601String();
  final normalizedName = normalizeName(name);
  final presentation = inferPresentation(name);
  final rawPayload = <String, Object?>{
    'source': 'chedraui_product_page',
    'product_id': productId,
    'json_ld_product': product,
    'price_evidence': 'sku_bound_json_ld_offer',
  };

  final record = <String, Object?>{
    'source': 'chedraui-mx',
    'store_brand': 'Chedraui',
    'store_slug': 'chedraui-online',
    'price_scope': 'online',
    'source_product_name': name,
    'normalized_name': normalizedName,
    'category': 'Supermercado',
    'presentation': presentation,
    'price': price,
    'currency': 'MXN',
    'available': available,
    'captured_at': now,
    'observed_at': now,
    'source_url': productUrl,
    'evidence_kind': 'product_page',
    'confidence_score': 0.90,
    'is_synthetic': false,
    'review_status': 'accepted',
    'store_product_url': productUrl,
    'image_url': imageUrl,
    'external_reference': productId,
    'branch_external_key': null,
    'branch_name': null,
    'branch_address': null,
    'branch_municipality': null,
    'branch_state': null,
    'latitude': null,
    'longitude': null,
    'raw_payload': rawPayload,
  };

  record['content_hash'] = stableHash([
    record['source'],
    record['source_url'],
    record['price'],
    record['available'],
    record['observed_at'],
  ].join('|'));

  return record;
}

Iterable<Map<String, dynamic>> _jsonObjects(Object? value) sync* {
  if (value is Map<String, dynamic>) {
    yield value;
    for (final child in value.values) {
      yield* _jsonObjects(child);
    }
  } else if (value is List) {
    for (final child in value) {
      yield* _jsonObjects(child);
    }
  }
}

String? productUrlId(String url) {
  final match = RegExp(r'-([0-9]+)/p(?:$|[?#])').firstMatch(url);
  return match?.group(1);
}

bool _looksLikeProductUrl(String url) {
  return Uri.tryParse(url)?.scheme == 'https' &&
      Uri.tryParse(url)?.host == 'www.chedraui.com.mx' &&
      RegExp(r'-[0-9]+/p(?:$|[?#])').hasMatch(url);
}

String decodeJsonString(String value) {
  try {
    return jsonDecode('"$value"') as String;
  } on FormatException {
    return value.replaceAll(r'\/', '/');
  }
}

String htmlEntityDecode(String value) {
  return value
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
}

String inferPresentation(String name) {
  final pattern = RegExp(
    r'(\d+(?:[.,]\d+)?)\s*(kg|kilos?|g|gr|gramos?|l|lt|litros?|ml|piezas|pieza|pzas|pz)\b',
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

  final unitOnlyPattern = RegExp(
    r'\b(kg|kilos?|l|lt|litros?|piezas|pieza|pzas|pz)\b',
    caseSensitive: false,
  );
  final unitOnlyMatch = unitOnlyPattern.firstMatch(name);
  if (unitOnlyMatch != null) {
    return '1 ${canonicalPresentationUnit(unitOnlyMatch.group(1)!)}';
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

class RobotsRules {
  RobotsRules(this.rules);

  final List<RobotsRule> rules;

  static Future<RobotsRules> fetch({
    required HttpClient client,
    required String robotsUrl,
    required String userAgent,
  }) async {
    final body = await fetchText(
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
    required this.sitemapUrl,
    required this.robotsUrl,
    required this.userAgent,
    required this.limit,
    required this.delay,
    this.outputPath,
    this.urlsPath,
    this.evidenceDirectory,
    this.showHelp = false,
  });

  final String sitemapUrl;
  final String robotsUrl;
  final String userAgent;
  final int limit;
  final Duration delay;
  final String? outputPath;
  final String? urlsPath;
  final String? evidenceDirectory;
  final bool showHelp;

  static ScraperOptions parse(List<String> args) {
    var sitemapUrl = defaultSitemapUrl;
    var robotsUrl = defaultRobotsUrl;
    var userAgent = defaultUserAgent;
    var limit = 5;
    var delayMs = 1500;
    String? outputPath;
    String? urlsPath;
    String? evidenceDirectory;

    for (var index = 0; index < args.length; index++) {
      final arg = args[index];
      if (arg == '--help' || arg == '-h') {
        return ScraperOptions(
          sitemapUrl: sitemapUrl,
          robotsUrl: robotsUrl,
          userAgent: userAgent,
          limit: limit,
          delay: Duration(milliseconds: delayMs),
          outputPath: outputPath,
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
        case '--sitemap':
          sitemapUrl = readValue();
        case '--robots':
          robotsUrl = readValue();
        case '--user-agent':
          userAgent = readValue();
        case '--limit':
          limit = int.parse(readValue());
        case '--delay-ms':
          delayMs = int.parse(readValue());
        case '--out':
          outputPath = readValue();
        case '--urls':
          urlsPath = readValue();
        case '--evidence-dir':
          evidenceDirectory = readValue();
        default:
          throw ArgumentError('Unknown argument: $arg');
      }
    }

    if (limit <= 0) {
      throw ArgumentError('--limit must be greater than 0');
    }
    if (delayMs < 0) {
      throw ArgumentError('--delay-ms cannot be negative');
    }

    return ScraperOptions(
      sitemapUrl: sitemapUrl,
      robotsUrl: robotsUrl,
      userAgent: userAgent,
      limit: limit,
      delay: Duration(milliseconds: delayMs),
      outputPath: outputPath,
      urlsPath: urlsPath,
      evidenceDirectory: evidenceDirectory,
    );
  }

  static const helpText = '''
Usage:
  dart run tools/ingestion/bin/chedraui_sitemap_scraper.dart [options]

Options:
  --sitemap <url>      Product sitemap or sitemap index URL.
  --urls <path>        JSON array of reviewed product URLs instead of a sitemap.
  --evidence-dir <dir> New directory for HTML and observation receipts.
  --robots <url>       robots.txt URL to enforce before fetching.
  --limit <n>          Number of product price records to emit. Default: 5.
  --delay-ms <n>       Delay between product page fetches. Default: 1500.
  --out <path>         Write NDJSON to a file instead of stdout.
  --user-agent <ua>    Identifiable crawler User-Agent.
  --help              Show this help.
''';
}
