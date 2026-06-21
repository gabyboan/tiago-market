import 'dart:async';
import 'dart:convert';
import 'dart:io';

const defaultSitemapUrl = 'https://www.steren.com.mx/pub/mexico/sitemap.xml';
const defaultRobotsUrl = 'https://www.steren.com.mx/robots.txt';
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

    final productUrls = await discoverProductUrls(
      client: client,
      sitemapUrl: options.sitemapUrl,
      userAgent: options.userAgent,
      limit: options.limit * 3,
      robots: robots,
    );

    final outputFile = options.outputPath == null
        ? null
        : File(options.outputPath!).openWrite(mode: FileMode.writeOnly);
    final sink = outputFile ?? stdout;
    var emitted = 0;

    try {
      for (final productUrl in productUrls) {
        if (!robots.isAllowed(productUrl)) {
          stderr.writeln('robots.txt skipped $productUrl');
          continue;
        }

        final page = await fetchText(
          client: client,
          url: productUrl,
          userAgent: options.userAgent,
        );
        final record = parseSterenProductPage(
          productUrl: productUrl,
          html: page,
        );

        if (record == null) {
          stderr.writeln('No publishable price evidence found at $productUrl');
        } else {
          sink.writeln(jsonEncode(record));
          emitted++;
        }

        if (emitted >= options.limit) {
          break;
        }
        await Future<void>.delayed(options.delay);
      }
    } finally {
      if (outputFile != null) {
        await outputFile.flush();
        await outputFile.close();
      }
    }

    stderr.writeln('Generated $emitted Steren staging record(s).');
  } finally {
    client.close(force: true);
  }
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
    final urls = <String>[];

    for (final childSitemap in locs.where(robots.isAllowed)) {
      final childXml = await fetchText(
        client: client,
        url: childSitemap,
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
  request.headers
    ..set(HttpHeaders.userAgentHeader, userAgent)
    ..set(HttpHeaders.acceptHeader, 'text/html,application/xml;q=0.9,*/*;q=0.8')
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

List<String> extractXmlLocs(String xml) {
  final locPattern = RegExp(r'<loc>\s*([^<]+?)\s*</loc>', caseSensitive: false);
  return locPattern
      .allMatches(xml)
      .map((match) => htmlEntityDecode(match.group(1)!.trim()))
      .toList();
}

Map<String, Object?>? parseSterenProductPage({
  required String productUrl,
  required String html,
}) {
  final product = _findJsonLdProduct(html);
  if (product == null) {
    return null;
  }

  final offer = _firstMap(product['offers']) ?? const <String, Object?>{};
  final name = _cleanText(_firstString(product['name']));
  final sku =
      _cleanText(_firstString(offer['sku']) ?? _firstString(product['sku']));
  final price = _priceFromValue(offer['price']) ??
      _priceFromValue(_metaContent(html, 'product:price:amount'));
  final currency = _cleanText(
        _firstString(offer['priceCurrency']) ??
            _metaContent(html, 'product:price:currency'),
      ) ??
      'MXN';

  if (name == null || price == null || price <= 0 || currency != 'MXN') {
    return null;
  }

  final productPageUrl = _cleanText(_firstString(offer['url'])) ?? productUrl;
  final imageUrl = _cleanText(
    _firstString(product['image']) ?? _metaContent(html, 'og:image'),
  );
  final category =
      _cleanText(_firstString(product['category'])) ?? 'Electronica';
  final availabilityText = _cleanText(
        _firstString(offer['availability']) ??
            _metaContent(html, 'product:availability'),
      ) ??
      '';
  final available = _isAvailable(availabilityText);
  final now = DateTime.now().toUtc().toIso8601String();
  final normalizedName = normalizeName(name);
  final presentation = inferPresentation(name);
  final rawPayload = <String, Object?>{
    'source': 'steren_product_page',
    'sku': sku,
    'model': _cleanText(_firstString(product['model'])),
    'price_valid_until': _cleanText(_firstString(offer['priceValidUntil'])),
    'availability': availabilityText,
    'json_ld_product': product,
  };

  final record = <String, Object?>{
    'source': 'steren-mx',
    'store_brand': 'Steren',
    'store_slug': 'steren-online',
    'source_product_name': name,
    'normalized_name': normalizedName,
    'category': category,
    'presentation': presentation,
    'price': price,
    'currency': currency,
    'available': available,
    'captured_at': now,
    'observed_at': now,
    'source_url': productPageUrl,
    'evidence_kind': 'product_page',
    'confidence_score': 0.90,
    'is_synthetic': false,
    'review_status': 'pending',
    'store_product_url': productPageUrl,
    'image_url': imageUrl,
    'external_reference': sku,
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
  ].join('|'));

  return record;
}

bool _looksLikeProductUrl(String url) {
  final uri = Uri.tryParse(url);
  return uri?.host == 'www.steren.com.mx' &&
      uri!.path.endsWith('.html') &&
      !uri.path.contains('/blog/');
}

Map<String, dynamic>? _findJsonLdProduct(String html) {
  final pattern = RegExp(
    r'''<script\b[^>]*type=["']application/ld\+json["'][^>]*>(.*?)</script>''',
    caseSensitive: false,
    dotAll: true,
  );

  for (final match in pattern.allMatches(html)) {
    final body = htmlEntityDecode(match.group(1)!.trim());
    try {
      final decoded = jsonDecode(body);
      final product = _findProductMap(decoded);
      if (product != null) {
        return product;
      }
    } on FormatException {
      continue;
    }
  }

  return null;
}

Map<String, dynamic>? _findProductMap(Object? value) {
  if (value is Map) {
    if (_isProductType(value['@type'])) {
      return Map<String, dynamic>.from(value);
    }

    for (final child in value.values) {
      final product = _findProductMap(child);
      if (product != null) {
        return product;
      }
    }
  } else if (value is List) {
    for (final child in value) {
      final product = _findProductMap(child);
      if (product != null) {
        return product;
      }
    }
  }

  return null;
}

bool _isProductType(Object? value) {
  if (value is String) {
    return value.toLowerCase() == 'product';
  }
  if (value is List) {
    return value.any(_isProductType);
  }
  return false;
}

Map<String, dynamic>? _firstMap(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  if (value is List) {
    for (final item in value) {
      final map = _firstMap(item);
      if (map != null) {
        return map;
      }
    }
  }
  return null;
}

String? _firstString(Object? value) {
  if (value is String) {
    return value;
  }
  if (value is List) {
    for (final item in value) {
      final text = _firstString(item);
      if (text != null) {
        return text;
      }
    }
  }
  if (value is Map) {
    return _firstString(value['url']) ?? _firstString(value['@id']);
  }
  return null;
}

double? _priceFromValue(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    final normalized = value.replaceAll(',', '').trim();
    return double.tryParse(normalized);
  }
  return null;
}

String? _metaContent(String html, String property) {
  final metaPattern = RegExp(
    r'<meta\b([^>]+)>',
    caseSensitive: false,
    dotAll: true,
  );
  for (final match in metaPattern.allMatches(html)) {
    final attrs = match.group(1)!;
    final propertyValue =
        _htmlAttribute(attrs, 'property') ?? _htmlAttribute(attrs, 'name');
    if (propertyValue != property) {
      continue;
    }
    final content = _htmlAttribute(attrs, 'content');
    if (content != null && content.trim().isNotEmpty) {
      return htmlEntityDecode(content.trim());
    }
  }
  return null;
}

String? _htmlAttribute(String text, String attribute) {
  final pattern = RegExp(
    "${RegExp.escape(attribute)}\\s*=\\s*[\"']([^\"']*)[\"']",
    caseSensitive: false,
    dotAll: true,
  );
  return pattern.firstMatch(text)?.group(1);
}

String? _cleanText(String? value) {
  if (value == null) {
    return null;
  }
  final cleaned = htmlEntityDecode(value)
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(r'\/', '/')
      .trim();
  return cleaned.isEmpty ? null : cleaned;
}

bool _isAvailable(String value) {
  final normalized = value.toLowerCase();
  if (normalized.contains('outofstock') ||
      normalized.contains('out of stock') ||
      normalized.contains('agotado') ||
      normalized.contains('discontinued')) {
    return false;
  }
  return true;
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
    this.showHelp = false,
  });

  final String sitemapUrl;
  final String robotsUrl;
  final String userAgent;
  final int limit;
  final Duration delay;
  final String? outputPath;
  final bool showHelp;

  static ScraperOptions parse(List<String> args) {
    var sitemapUrl = defaultSitemapUrl;
    var robotsUrl = defaultRobotsUrl;
    var userAgent = defaultUserAgent;
    var limit = 5;
    var delayMs = 1500;
    String? outputPath;

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
    );
  }

  static const helpText = '''
Usage:
  dart run tools/ingestion/bin/steren_sitemap_scraper.dart [options]

Options:
  --sitemap <url>      Product sitemap or sitemap index URL.
  --robots <url>       robots.txt URL to enforce before fetching.
  --limit <n>          Number of product price records to emit. Default: 5.
  --delay-ms <n>       Delay between product page fetches. Default: 1500.
  --out <path>         Write NDJSON to a file instead of stdout.
  --user-agent <ua>    Identifiable crawler User-Agent.
  --help               Show this help.
''';
}
