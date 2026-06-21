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

    final sitemapUrls = await discoverProductUrls(
      client: client,
      sitemapUrl: options.sitemapUrl,
      userAgent: options.userAgent,
      limit: options.limit,
      robots: robots,
    );

    final outputFile = options.outputPath == null
        ? null
        : File(options.outputPath!).openWrite(mode: FileMode.writeOnly);
    final sink = outputFile ?? stdout;
    var emitted = 0;

    try {
      for (final productUrl in sitemapUrls) {
        if (!robots.isAllowed(productUrl)) {
          stderr.writeln('robots.txt skipped $productUrl');
          continue;
        }

        final page = await fetchText(
          client: client,
          url: productUrl,
          userAgent: options.userAgent,
        );
        final record = parseChedrauiProductPage(
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

    stderr.writeln('Generated $emitted Chedraui staging record(s).');
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

Map<String, Object?>? parseChedrauiProductPage({
  required String productUrl,
  required String html,
}) {
  final productId = productUrlId(productUrl);
  if (productId == null) {
    return null;
  }

  final name = _firstJsonStringAfter(
        html,
        RegExp('"itemId":"$productId"'),
        '"name"',
      ) ??
      _firstJsonString(
        html,
        RegExp(r'"productName"\s*:\s*"((?:\\.|[^"\\])*)"'),
      );
  final priceFromOffer = _firstNumberNear(
    html,
    RegExp('"sku=$productId[^"]*?[&?]price=(\\d+)"'),
  );
  final priceFromState = _firstNumberNear(
    html,
    RegExp(r'"Price"\s*:\s*([0-9]+(?:\.[0-9]+)?)'),
  );
  final price = priceFromOffer == null ? priceFromState : priceFromOffer / 100;
  final availableQuantity = _firstInt(
    html,
    RegExp(r'"AvailableQuantity"\s*:\s*([0-9]+)'),
  );
  final imageUrl = _firstJsonString(
    html,
    RegExp(r'"imageUrl"\s*:\s*"((?:\\.|[^"\\])*)"'),
  );
  final priceValidUntil = _firstJsonString(
    html,
    RegExp(r'"PriceValidUntil"\s*:\s*"((?:\\.|[^"\\])*)"'),
  );
  final ean = _firstJsonStringAfter(
    html,
    RegExp('"itemId":"$productId"'),
    '"ean"',
  );

  if (name == null || price == null || price <= 0) {
    return null;
  }

  final now = DateTime.now().toUtc().toIso8601String();
  final normalizedName = normalizeName(name);
  final presentation = inferPresentation(name);
  final rawPayload = <String, Object?>{
    'source': 'chedraui_product_page',
    'product_id': productId,
    'ean': ean,
    'available_quantity': availableQuantity,
    'price_valid_until': priceValidUntil,
    'price_evidence': priceFromOffer == null
        ? 'embedded_vtex_state_price'
        : 'embedded_add_to_cart_price',
  };

  final record = <String, Object?>{
    'source': 'chedraui-mx',
    'store_brand': 'Chedraui',
    'store_slug': 'chedraui-online',
    'source_product_name': name,
    'normalized_name': normalizedName,
    'category': 'Supermercado',
    'presentation': presentation,
    'price': price,
    'currency': 'MXN',
    'available': availableQuantity == null ? true : availableQuantity > 0,
    'captured_at': now,
    'observed_at': now,
    'source_url': productUrl,
    'evidence_kind': 'product_page',
    'confidence_score': 0.90,
    'is_synthetic': false,
    'review_status': 'pending',
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
  ].join('|'));

  return record;
}

String? productUrlId(String url) {
  final match = RegExp(r'-([0-9]+)/p(?:$|[?#])').firstMatch(url);
  return match?.group(1);
}

bool _looksLikeProductUrl(String url) {
  return Uri.tryParse(url)?.host == 'www.chedraui.com.mx' &&
      RegExp(r'-[0-9]+/p(?:$|[?#])').hasMatch(url);
}

String? _firstJsonString(String text, RegExp pattern) {
  final match = pattern.firstMatch(text);
  final value = match?.group(1);
  if (value == null) {
    return null;
  }
  return decodeJsonString(value);
}

String? _firstJsonStringAfter(String text, Pattern anchor, String key) {
  final anchorMatch = anchor is RegExp
      ? anchor.firstMatch(text)
      : RegExp(RegExp.escape(anchor.toString())).firstMatch(text);
  if (anchorMatch == null) {
    return null;
  }

  final start = anchorMatch.start;
  final end = start + 8000 > text.length ? text.length : start + 8000;
  final window = text.substring(start, end);
  final pattern = RegExp(
    '${RegExp.escape(key)}\\s*:\\s*"((?:\\\\.|[^"\\\\])*)"',
  );
  return _firstJsonString(window, pattern);
}

double? _firstNumberNear(String text, RegExp pattern) {
  final match = pattern.firstMatch(text);
  final value = match?.group(1);
  if (value == null) {
    return null;
  }
  return double.tryParse(value);
}

int? _firstInt(String text, RegExp pattern) {
  final match = pattern.firstMatch(text);
  final value = match?.group(1);
  if (value == null) {
    return null;
  }
  return int.tryParse(value);
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
  dart run tools/ingestion/bin/chedraui_sitemap_scraper.dart [options]

Options:
  --sitemap <url>      Product sitemap or sitemap index URL.
  --robots <url>       robots.txt URL to enforce before fetching.
  --limit <n>          Number of product price records to emit. Default: 5.
  --delay-ms <n>       Delay between product page fetches. Default: 1500.
  --out <path>         Write NDJSON to a file instead of stdout.
  --user-agent <ua>    Identifiable crawler User-Agent.
  --help              Show this help.
''';
}
