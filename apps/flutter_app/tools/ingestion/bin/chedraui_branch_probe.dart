import 'dart:convert';
import 'dart:io';

import 'chedraui_sitemap_scraper.dart' as sitemap;

const defaultRobotsUrl = 'https://www.chedraui.com.mx/robots.txt';
const defaultSessionUrl = 'https://www.chedraui.com.mx/api/sessions';
const defaultUserAgent =
    'TiagoMarketBot/0.1 (+https://tiago-market.local/contact)';

Future<void> main(List<String> args) async {
  final options = ProbeOptions.parse(args);
  if (options.showHelp) {
    stdout.writeln(ProbeOptions.helpText);
    return;
  }

  final runner = ChedrauiBranchProbe(options);
  final result = await runner.run();
  stdout.writeln(result.report);
  if (result.classification == ProbeClassification.blocked) {
    exitCode = 2;
  }
}

enum ProbeClassification {
  confirmedBranchLocal,
  onlineOnly,
  ambiguous,
  blocked,
}

extension ProbeClassificationWire on ProbeClassification {
  String get wireValue => switch (this) {
    ProbeClassification.confirmedBranchLocal => 'confirmed_branch_local',
    ProbeClassification.onlineOnly => 'online_only',
    ProbeClassification.ambiguous => 'ambiguous',
    ProbeClassification.blocked => 'blocked',
  };
}

class ChedrauiBranchProbe {
  ChedrauiBranchProbe(this.options);

  final ProbeOptions options;

  Future<ProbeRunResult> run() async {
    _validateScope();
    final outputDirectory = Directory(options.outputDirectory);
    await outputDirectory.create(recursive: true);
    final artifacts = ArtifactWriter(outputDirectory);
    final startedAt = DateTime.now().toUtc();
    final outcomes = <BranchOutcome>[];
    ProductSnapshot? baseline;
    String? globalBlockReason;

    final publicClient = _newClient();
    try {
      final robotsResponse = await _request(
        publicClient,
        method: 'GET',
        uri: Uri.parse(options.robotsUrl),
        accept: 'text/plain',
      );
      await artifacts.writeResponse('robots', robotsResponse);

      if (robotsResponse.statusCode != HttpStatus.ok) {
        globalBlockReason =
            'robots.txt returned HTTP ${robotsResponse.statusCode}.';
      } else {
        final robots = sitemap.RobotsRules.parse(robotsResponse.body);
        final productAllowed = robots.isAllowed(options.productUrl);
        final sessionAllowed = robots.isAllowed(options.sessionUrl);
        await artifacts.writeJson('robots-check.json', {
          'robots_url': options.robotsUrl,
          'product_url': options.productUrl,
          'product_allowed': productAllowed,
          'session_url': options.sessionUrl,
          'session_allowed': sessionAllowed,
          'captured_at': robotsResponse.capturedAt,
        });

        if (!productAllowed || !sessionAllowed) {
          globalBlockReason =
              'robots.txt does not allow every route required by the probe.';
        } else {
          final baselineResponse = await _request(
            publicClient,
            method: 'GET',
            uri: Uri.parse(options.productUrl),
            accept: 'text/html',
          );
          await artifacts.writeResponse(
            'online-baseline-product',
            baselineResponse,
            extension: 'html',
          );
          baseline = parseProductSnapshot(
            productUrl: options.productUrl,
            expectedSku: options.sku,
            response: baselineResponse,
          );
          await artifacts.writeJson(
            'online-baseline-observation.json',
            baseline?.toJson() ??
                {
                  'sku': options.sku,
                  'evidence_url': options.productUrl,
                  'captured_at': baselineResponse.capturedAt,
                  'error': 'No complete public product offer was parsed.',
                },
          );

          if (_isBlockedResponse(baselineResponse)) {
            globalBlockReason = _blockedReason(
              'online product page',
              baselineResponse,
            );
          }
        }
      }
    } on Object catch (error) {
      globalBlockReason = 'Public preflight failed: $error';
    } finally {
      publicClient.close(force: true);
    }

    if (globalBlockReason == null) {
      for (var index = 0; index < options.branches.length; index++) {
        final branch = options.branches[index];
        final outcome = await _probeBranch(
          branch: branch,
          ordinal: index + 1,
          artifacts: artifacts,
        );
        outcomes.add(outcome);

        if (outcome.blocked) {
          globalBlockReason = outcome.reason;
          for (
            var remaining = index + 1;
            remaining < options.branches.length;
            remaining++
          ) {
            outcomes.add(
              BranchOutcome.notAttempted(
                options.branches[remaining],
                'Not attempted after a blocking response on the public flow.',
              ),
            );
          }
          break;
        }
      }
    } else {
      for (final branch in options.branches) {
        outcomes.add(BranchOutcome.notAttempted(branch, globalBlockReason));
      }
    }

    final classification = classifyProbe(
      outcomes,
      globalBlockReason: globalBlockReason,
    );
    final completedAt = DateTime.now().toUtc();
    final report = buildHumanReport(
      classification: classification,
      baseline: baseline,
      outcomes: outcomes,
      artifactDirectory: outputDirectory.path,
      startedAt: startedAt,
      completedAt: completedAt,
      globalBlockReason: globalBlockReason,
    );
    await artifacts.writeText('report.txt', '$report\n');
    await artifacts.writeJson('summary.json', {
      'classification': classification.wireValue,
      'publication_ready':
          classification == ProbeClassification.confirmedBranchLocal,
      'started_at': startedAt.toIso8601String(),
      'completed_at': completedAt.toIso8601String(),
      'sku': options.sku,
      'product_url': options.productUrl,
      'block_reason': globalBlockReason,
      'baseline': baseline?.toJson(),
      'branches': outcomes.map((outcome) => outcome.toJson()).toList(),
      'artifacts_directory': outputDirectory.path,
      'guardrails': {
        'ndjson_emitted': false,
        'imports_executed': false,
        'checkout_called': false,
        'credentials_used': false,
        'cookies_persisted': false,
      },
    });
    await artifacts.writeManifest();

    return ProbeRunResult(
      classification: classification,
      report: report,
      artifactDirectory: outputDirectory.path,
    );
  }

  Future<BranchOutcome> _probeBranch({
    required BranchTarget branch,
    required int ordinal,
    required ArtifactWriter artifacts,
  }) async {
    final client = _newClient();
    final prefix = 'branch-$ordinal-${_safeName(branch.externalKey)}';
    try {
      final requestBody = {
        'public': {
          'country': {'value': 'MEX'},
          'regionId': {'value': branch.encodedRegionId},
        },
      };
      await artifacts.writeJson('$prefix-session-request.json', requestBody);
      final sessionResponse = await _request(
        client,
        method: 'POST',
        uri: Uri.parse(options.sessionUrl),
        accept: 'application/json',
        jsonBody: requestBody,
      );
      await artifacts.writeResponse(
        '$prefix-session-response',
        sessionResponse,
        sanitizeSessionJson: true,
      );

      if (_isBlockedResponse(sessionResponse)) {
        return BranchOutcome.blocked(
          branch,
          _blockedReason(
            'session selection for ${branch.name}',
            sessionResponse,
          ),
          sessionStatusCode: sessionResponse.statusCode,
        );
      }
      if (sessionResponse.statusCode < 200 ||
          sessionResponse.statusCode >= 300) {
        return BranchOutcome.ambiguous(
          branch,
          'Session selection returned HTTP ${sessionResponse.statusCode}.',
          sessionStatusCode: sessionResponse.statusCode,
        );
      }

      final sessionContext = parseSessionContext(sessionResponse.body);
      final inMemoryCookies = _allowedAnonymousCookies(
        sessionResponse,
        sessionContext,
      );
      final productResponse = await _request(
        client,
        method: 'GET',
        uri: Uri.parse(options.productUrl),
        accept: 'text/html',
        cookies: inMemoryCookies,
      );
      await artifacts.writeResponse(
        '$prefix-product',
        productResponse,
        extension: 'html',
      );

      if (_isBlockedResponse(productResponse)) {
        return BranchOutcome.blocked(
          branch,
          _blockedReason('product page for ${branch.name}', productResponse),
          sessionStatusCode: sessionResponse.statusCode,
          productStatusCode: productResponse.statusCode,
        );
      }

      final snapshot = parseProductSnapshot(
        productUrl: options.productUrl,
        expectedSku: options.sku,
        response: productResponse,
      );
      final observedRegionId =
          extractEmbeddedRegionId(productResponse.body) ??
          sessionContext.decodedRegionId;
      final attributable =
          snapshot != null &&
          observedRegionId == branch.rawRegionId &&
          snapshot.sku == options.sku;
      final outcome = BranchOutcome.observed(
        branch: branch,
        snapshot: snapshot,
        observedRegionId: observedRegionId,
        attributable: attributable,
        sessionStatusCode: sessionResponse.statusCode,
        productStatusCode: productResponse.statusCode,
        reason: attributable
            ? 'Product offer retained the expected branch region identifier.'
            : 'The product observation did not retain the expected branch region identifier.',
      );
      await artifacts.writeJson('$prefix-observation.json', outcome.toJson());
      return outcome;
    } on Object catch (error) {
      return BranchOutcome.blocked(
        branch,
        'Public branch probe failed: $error',
      );
    } finally {
      client.close(force: true);
    }
  }

  HttpClient _newClient() {
    return HttpClient()
      ..autoUncompress = true
      ..connectionTimeout = options.timeout;
  }

  Future<HttpResponseData> _request(
    HttpClient client, {
    required String method,
    required Uri uri,
    required String accept,
    Map<String, Object?>? jsonBody,
    List<Cookie> cookies = const [],
  }) async {
    final request = await client.openUrl(method, uri);
    request.followRedirects = true;
    request.maxRedirects = 3;
    request.headers
      ..set(HttpHeaders.userAgentHeader, options.userAgent)
      ..set(HttpHeaders.acceptHeader, accept)
      ..set(HttpHeaders.acceptEncodingHeader, 'gzip, deflate')
      ..set(HttpHeaders.refererHeader, 'https://www.chedraui.com.mx/');
    if (method == 'POST') {
      request.headers
        ..set(HttpHeaders.contentTypeHeader, 'application/json')
        ..set('Origin', 'https://www.chedraui.com.mx');
    }
    for (final cookie in cookies) {
      request.cookies.add(Cookie(cookie.name, cookie.value));
    }
    if (jsonBody != null) {
      request.write(jsonEncode(jsonBody));
    }

    final response = await request.close();
    final body = await utf8.decodeStream(response);
    final safeHeaders = <String, List<String>>{};
    for (final name in const [
      HttpHeaders.contentTypeHeader,
      HttpHeaders.dateHeader,
      HttpHeaders.cacheControlHeader,
      'x-request-id',
      'x-vtex-cache-status',
      'x-vtex-janus-router-backend-app',
    ]) {
      final values = response.headers[name];
      if (values != null) {
        safeHeaders[name] = values;
      }
    }

    return HttpResponseData(
      requestedUri: uri,
      finalUri: response.redirects.isEmpty
          ? uri
          : response.redirects.last.location,
      statusCode: response.statusCode,
      body: body,
      safeHeaders: safeHeaders,
      cookies: response.cookies
          .map((cookie) => Cookie(cookie.name, cookie.value))
          .toList(growable: false),
      capturedAt: DateTime.now().toUtc().toIso8601String(),
      redirectedToLogin: response.redirects.any(
        (redirect) =>
            redirect.location.path.startsWith('/login') ||
            redirect.location.path.startsWith('/account'),
      ),
    );
  }

  void _validateScope() {
    if (options.branches.length != 2) {
      throw ArgumentError('Exactly two --branch targets are required.');
    }
    final product = Uri.parse(options.productUrl);
    final robots = Uri.parse(options.robotsUrl);
    final session = Uri.parse(options.sessionUrl);
    for (final uri in [product, robots, session]) {
      if (uri.scheme != 'https' || uri.host != 'www.chedraui.com.mx') {
        throw ArgumentError(
          'Only public HTTPS routes on chedraui.com.mx are allowed.',
        );
      }
      final lowerPath = uri.path.toLowerCase();
      if (lowerPath.startsWith('/checkout') ||
          lowerPath.startsWith('/login') ||
          lowerPath.startsWith('/account')) {
        throw ArgumentError(
          'Login, account and checkout routes are forbidden.',
        );
      }
    }
    if (session.path != '/api/sessions') {
      throw ArgumentError(
        '--session-url must use the public /api/sessions route.',
      );
    }
    if (!RegExp(r'-[0-9]+/p$').hasMatch(product.path)) {
      throw ArgumentError(
        '--product-url must be a public Chedraui product page.',
      );
    }
    if (options.branches.map((branch) => branch.externalKey).toSet().length !=
        2) {
      throw ArgumentError('The two branches must have distinct external keys.');
    }
  }
}

ProbeClassification classifyProbe(
  List<BranchOutcome> outcomes, {
  String? globalBlockReason,
}) {
  if (globalBlockReason != null || outcomes.any((outcome) => outcome.blocked)) {
    return ProbeClassification.blocked;
  }
  if (outcomes.length != 2 ||
      outcomes.any((outcome) => outcome.snapshot == null)) {
    return ProbeClassification.ambiguous;
  }

  final first = outcomes[0];
  final second = outcomes[1];
  final bothAttributable = first.attributable && second.attributable;
  final sameSku = first.snapshot!.sku == second.snapshot!.sku;
  final sameCurrency = first.snapshot!.currency == second.snapshot!.currency;
  final priceChanged = first.snapshot!.price != second.snapshot!.price;
  final availabilityChanged =
      first.snapshot!.available != second.snapshot!.available;
  final quantityChanged =
      first.snapshot!.availableQuantity != null &&
      second.snapshot!.availableQuantity != null &&
      first.snapshot!.availableQuantity != second.snapshot!.availableQuantity;

  if (bothAttributable &&
      sameSku &&
      sameCurrency &&
      (priceChanged || availabilityChanged || quantityChanged)) {
    return ProbeClassification.confirmedBranchLocal;
  }
  if (!first.attributable &&
      !second.attributable &&
      first.observedRegionId == null &&
      second.observedRegionId == null) {
    return ProbeClassification.onlineOnly;
  }
  return ProbeClassification.ambiguous;
}

ProductSnapshot? parseProductSnapshot({
  required String productUrl,
  required String expectedSku,
  required HttpResponseData response,
}) {
  if (response.statusCode < 200 || response.statusCode >= 300) {
    return null;
  }
  final record = sitemap.parseChedrauiProductPage(
    productUrl: productUrl,
    html: response.body,
  );
  if (record == null || record['external_reference'] != expectedSku) {
    return null;
  }
  final rawPayload = record['raw_payload'];
  final availableQuantity = rawPayload is Map
      ? rawPayload['available_quantity'] as int?
      : null;
  return ProductSnapshot(
    sku: expectedSku,
    name: record['source_product_name']! as String,
    price: (record['price']! as num).toDouble(),
    currency: record['currency']! as String,
    available: record['available']! as bool,
    availableQuantity: availableQuantity,
    evidenceUrl: productUrl,
    capturedAt: response.capturedAt,
  );
}

SessionContext parseSessionContext(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      return const SessionContext();
    }
    final segmentToken = decoded['segmentToken'] as String?;
    final sessionToken = decoded['sessionToken'] as String?;
    return SessionContext(
      segmentToken: segmentToken,
      sessionToken: sessionToken,
      decodedRegionId: decodeRegionFromSegmentToken(segmentToken),
    );
  } on FormatException {
    return const SessionContext();
  }
}

String? extractEmbeddedRegionId(String html) {
  final match = RegExp(r'"segmentToken":"([^"]+)"').firstMatch(html)?.group(1);
  return decodeRegionFromSegmentToken(match);
}

String? decodeRegionFromSegmentToken(String? segmentToken) {
  if (segmentToken == null || segmentToken.isEmpty) {
    return null;
  }
  try {
    final decoded = jsonDecode(
      utf8.decode(base64.decode(base64.normalize(segmentToken))),
    );
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    final encodedRegion = decoded['regionId'];
    if (encodedRegion is! String || encodedRegion.isEmpty) {
      return null;
    }
    return utf8.decode(base64.decode(base64.normalize(encodedRegion)));
  } on Object {
    return null;
  }
}

List<Cookie> _allowedAnonymousCookies(
  HttpResponseData response,
  SessionContext context,
) {
  const allowedNames = {'vtex_segment', 'vtex_session', 'VtexWorkspace'};
  final cookies = <String, Cookie>{};
  for (final cookie in response.cookies) {
    if (allowedNames.contains(cookie.name)) {
      cookies[cookie.name] = Cookie(cookie.name, cookie.value);
    }
  }
  if (!cookies.containsKey('vtex_segment') && context.segmentToken != null) {
    cookies['vtex_segment'] = Cookie('vtex_segment', context.segmentToken!);
  }
  if (!cookies.containsKey('vtex_session') && context.sessionToken != null) {
    cookies['vtex_session'] = Cookie('vtex_session', context.sessionToken!);
  }
  return cookies.values.toList(growable: false);
}

bool _isBlockedResponse(HttpResponseData response) {
  if ({401, 403, 429, 451}.contains(response.statusCode) ||
      response.redirectedToLogin) {
    return true;
  }
  final lower = response.body.toLowerCase();
  return lower.contains('too many requests') ||
      lower.contains('verify you are human') ||
      lower.contains('captcha challenge') ||
      lower.contains('cf-chl-captcha') ||
      lower.contains('access denied');
}

String _blockedReason(String step, HttpResponseData response) {
  if (response.redirectedToLogin) {
    return '$step redirected to login.';
  }
  final lower = response.body.toLowerCase();
  if (lower.contains('verify you are human') ||
      lower.contains('captcha challenge') ||
      lower.contains('cf-chl-captcha')) {
    return '$step required a captcha.';
  }
  return '$step was blocked with HTTP ${response.statusCode}.';
}

String buildHumanReport({
  required ProbeClassification classification,
  required ProductSnapshot? baseline,
  required List<BranchOutcome> outcomes,
  required String artifactDirectory,
  required DateTime startedAt,
  required DateTime completedAt,
  required String? globalBlockReason,
}) {
  final buffer = StringBuffer()
    ..writeln('Chedraui Mexico branch probe')
    ..writeln('classification: ${classification.wireValue}')
    ..writeln(
      'publication_ready: ${classification == ProbeClassification.confirmedBranchLocal ? 'yes' : 'no'}',
    )
    ..writeln('started_at: ${startedAt.toIso8601String()}')
    ..writeln('completed_at: ${completedAt.toIso8601String()}')
    ..writeln('artifacts: $artifactDirectory');
  if (globalBlockReason != null) {
    buffer.writeln('block_reason: $globalBlockReason');
  }
  if (baseline != null) {
    buffer
      ..writeln()
      ..writeln('Online baseline')
      ..writeln(
        '  sku=${baseline.sku} price=${baseline.price.toStringAsFixed(2)} '
        '${baseline.currency} stock=${baseline.availableQuantity ?? 'unknown'} '
        'available=${baseline.available}',
      );
  }

  for (final outcome in outcomes) {
    buffer
      ..writeln()
      ..writeln('${outcome.branch.externalKey} | ${outcome.branch.name}')
      ..writeln('  address: ${outcome.branch.address}')
      ..writeln('  expected_region: ${outcome.branch.rawRegionId}')
      ..writeln('  observed_region: ${outcome.observedRegionId ?? 'none'}')
      ..writeln('  attributable: ${outcome.attributable ? 'yes' : 'no'}')
      ..writeln('  result: ${outcome.state}')
      ..writeln('  reason: ${outcome.reason}');
    if (outcome.snapshot != null) {
      buffer.writeln(
        '  sku=${outcome.snapshot!.sku} '
        'price=${outcome.snapshot!.price.toStringAsFixed(2)} '
        '${outcome.snapshot!.currency} '
        'stock=${outcome.snapshot!.availableQuantity ?? 'unknown'} '
        'available=${outcome.snapshot!.available}',
      );
    }
  }

  buffer
    ..writeln()
    ..writeln('Guardrails')
    ..writeln('  NDJSON/imports: disabled')
    ..writeln('  login/account/checkout: not used')
    ..writeln('  persisted cookies or credentials: none');
  return buffer.toString().trimRight();
}

class ProbeOptions {
  ProbeOptions({
    required this.branches,
    required this.productUrl,
    required this.sku,
    required this.outputDirectory,
    required this.robotsUrl,
    required this.sessionUrl,
    required this.userAgent,
    required this.timeout,
    this.showHelp = false,
  });

  final List<BranchTarget> branches;
  final String productUrl;
  final String sku;
  final String outputDirectory;
  final String robotsUrl;
  final String sessionUrl;
  final String userAgent;
  final Duration timeout;
  final bool showHelp;

  static ProbeOptions parse(List<String> args) {
    final branches = <BranchTarget>[];
    String? productUrl;
    String? sku;
    String? outputDirectory;
    var robotsUrl = defaultRobotsUrl;
    var sessionUrl = defaultSessionUrl;
    var userAgent = defaultUserAgent;
    var timeoutMs = 20000;

    for (var index = 0; index < args.length; index++) {
      final arg = args[index];
      if (arg == '--help' || arg == '-h') {
        return ProbeOptions(
          branches: const [],
          productUrl: '',
          sku: '',
          outputDirectory: '',
          robotsUrl: robotsUrl,
          sessionUrl: sessionUrl,
          userAgent: userAgent,
          timeout: Duration(milliseconds: timeoutMs),
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
        case '--branch':
          branches.add(BranchTarget.parse(readValue()));
        case '--product-url':
          productUrl = readValue();
        case '--sku':
          sku = readValue();
        case '--out-dir':
          outputDirectory = readValue();
        case '--robots':
          robotsUrl = readValue();
        case '--session-url':
          sessionUrl = readValue();
        case '--user-agent':
          userAgent = readValue();
        case '--timeout-ms':
          timeoutMs = int.parse(readValue());
        default:
          throw ArgumentError('Unknown argument: $arg');
      }
    }

    if (productUrl == null) {
      throw ArgumentError('--product-url is required.');
    }
    sku ??= sitemap.productUrlId(productUrl);
    if (sku == null || sku.isEmpty) {
      throw ArgumentError('--sku is required when it cannot be inferred.');
    }
    if (timeoutMs <= 0) {
      throw ArgumentError('--timeout-ms must be greater than zero.');
    }
    outputDirectory ??=
        '${Directory.systemTemp.path}/chedraui_branch_probe_${DateTime.now().toUtc().microsecondsSinceEpoch}';

    return ProbeOptions(
      branches: branches,
      productUrl: productUrl,
      sku: sku,
      outputDirectory: outputDirectory,
      robotsUrl: robotsUrl,
      sessionUrl: sessionUrl,
      userAgent: userAgent,
      timeout: Duration(milliseconds: timeoutMs),
    );
  }

  static const helpText = '''
Usage:
  dart run tools/ingestion/bin/chedraui_branch_probe.dart \\
    --branch 'external_key|name|address|SW#region_id' \\
    --branch 'external_key|name|address|SW#region_id' \\
    --product-url 'https://www.chedraui.com.mx/product-name-123/p' \\
    [--sku 123] [--out-dir /tmp/chedraui-branch-probe]

The probe performs one online baseline and at most one public session/product
observation per branch. It never calls login, account, checkout or Supabase,
never emits NDJSON, and never persists cookies.

Options:
  --branch <spec>       Repeat exactly twice. Format:
                        external_key|name|address|decoded_region_id
  --product-url <url>   One public Chedraui product page.
  --sku <id>            Product/SKU ID; inferred from the URL when omitted.
  --out-dir <path>      Artifact directory. Defaults to a unique /tmp path.
  --robots <url>        robots.txt URL.
  --session-url <url>   Public session route; must be /api/sessions.
  --user-agent <ua>     Identifiable crawler User-Agent.
  --timeout-ms <n>      Per-request timeout. Default: 20000.
  --help                Show this help.
''';
}

class BranchTarget {
  const BranchTarget({
    required this.externalKey,
    required this.name,
    required this.address,
    required this.rawRegionId,
  });

  final String externalKey;
  final String name;
  final String address;
  final String rawRegionId;

  String get encodedRegionId => base64.encode(utf8.encode(rawRegionId));

  factory BranchTarget.parse(String value) {
    final parts = value.split('|').map((part) => part.trim()).toList();
    if (parts.length != 4 || parts.any((part) => part.isEmpty)) {
      throw ArgumentError(
        '--branch must use external_key|name|address|decoded_region_id.',
      );
    }
    if (!parts[3].startsWith('SW#chedrauimx')) {
      throw ArgumentError(
        'Chedraui branch region IDs must start with SW#chedrauimx.',
      );
    }
    return BranchTarget(
      externalKey: parts[0],
      name: parts[1],
      address: parts[2],
      rawRegionId: parts[3],
    );
  }

  Map<String, Object?> toJson() => {
    'branch_external_key': externalKey,
    'branch_name': name,
    'address': address,
    'region_id': rawRegionId,
  };
}

class ProductSnapshot {
  const ProductSnapshot({
    required this.sku,
    required this.name,
    required this.price,
    required this.currency,
    required this.available,
    required this.availableQuantity,
    required this.evidenceUrl,
    required this.capturedAt,
  });

  final String sku;
  final String name;
  final double price;
  final String currency;
  final bool available;
  final int? availableQuantity;
  final String evidenceUrl;
  final String capturedAt;

  Map<String, Object?> toJson() => {
    'sku': sku,
    'product_name': name,
    'price': price,
    'currency': currency,
    'available': available,
    'available_quantity': availableQuantity,
    'evidence_url': evidenceUrl,
    'captured_at': capturedAt,
  };
}

class BranchOutcome {
  const BranchOutcome({
    required this.branch,
    required this.state,
    required this.reason,
    required this.blocked,
    required this.attributable,
    this.snapshot,
    this.observedRegionId,
    this.sessionStatusCode,
    this.productStatusCode,
  });

  final BranchTarget branch;
  final String state;
  final String reason;
  final bool blocked;
  final bool attributable;
  final ProductSnapshot? snapshot;
  final String? observedRegionId;
  final int? sessionStatusCode;
  final int? productStatusCode;

  factory BranchOutcome.observed({
    required BranchTarget branch,
    required ProductSnapshot? snapshot,
    required String? observedRegionId,
    required bool attributable,
    required String reason,
    required int sessionStatusCode,
    required int productStatusCode,
  }) {
    return BranchOutcome(
      branch: branch,
      state: snapshot == null ? 'incomplete' : 'observed',
      reason: reason,
      blocked: false,
      attributable: attributable,
      snapshot: snapshot,
      observedRegionId: observedRegionId,
      sessionStatusCode: sessionStatusCode,
      productStatusCode: productStatusCode,
    );
  }

  factory BranchOutcome.blocked(
    BranchTarget branch,
    String reason, {
    int? sessionStatusCode,
    int? productStatusCode,
  }) {
    return BranchOutcome(
      branch: branch,
      state: 'blocked',
      reason: reason,
      blocked: true,
      attributable: false,
      sessionStatusCode: sessionStatusCode,
      productStatusCode: productStatusCode,
    );
  }

  factory BranchOutcome.ambiguous(
    BranchTarget branch,
    String reason, {
    int? sessionStatusCode,
  }) {
    return BranchOutcome(
      branch: branch,
      state: 'ambiguous',
      reason: reason,
      blocked: false,
      attributable: false,
      sessionStatusCode: sessionStatusCode,
    );
  }

  factory BranchOutcome.notAttempted(BranchTarget branch, String? reason) {
    return BranchOutcome(
      branch: branch,
      state: 'not_attempted',
      reason: reason ?? 'Not attempted.',
      blocked: false,
      attributable: false,
    );
  }

  Map<String, Object?> toJson() => {
    ...branch.toJson(),
    'state': state,
    'reason': reason,
    'blocked': blocked,
    'attributable': attributable,
    'expected_region_id': branch.rawRegionId,
    'observed_region_id': observedRegionId,
    'session_status_code': sessionStatusCode,
    'product_status_code': productStatusCode,
    if (snapshot != null) ...snapshot!.toJson(),
  };
}

class SessionContext {
  const SessionContext({
    this.segmentToken,
    this.sessionToken,
    this.decodedRegionId,
  });

  final String? segmentToken;
  final String? sessionToken;
  final String? decodedRegionId;
}

class HttpResponseData {
  const HttpResponseData({
    required this.requestedUri,
    required this.finalUri,
    required this.statusCode,
    required this.body,
    required this.safeHeaders,
    required this.cookies,
    required this.capturedAt,
    required this.redirectedToLogin,
  });

  final Uri requestedUri;
  final Uri finalUri;
  final int statusCode;
  final String body;
  final Map<String, List<String>> safeHeaders;
  final List<Cookie> cookies;
  final String capturedAt;
  final bool redirectedToLogin;
}

class ArtifactWriter {
  ArtifactWriter(this.directory);

  final Directory directory;
  final List<Map<String, Object?>> _entries = [];

  Future<void> writeResponse(
    String stem,
    HttpResponseData response, {
    String extension = 'txt',
    bool sanitizeSessionJson = false,
  }) async {
    var body = response.body;
    if (sanitizeSessionJson) {
      body = _sanitizeSessionJson(body);
    }
    await writeText('$stem.$extension', body);
    await writeJson('$stem.metadata.json', {
      'requested_url': response.requestedUri.toString(),
      'final_url': response.finalUri.toString(),
      'status_code': response.statusCode,
      'captured_at': response.capturedAt,
      'headers': response.safeHeaders,
      'redirected_to_login': response.redirectedToLogin,
      'cookies_persisted': false,
      'body_sanitized': sanitizeSessionJson,
    });
  }

  Future<void> writeJson(String name, Object? value) {
    return writeText(
      name,
      '${const JsonEncoder.withIndent('  ').convert(value)}\n',
    );
  }

  Future<void> writeText(String name, String value) async {
    final file = File('${directory.path}/$name');
    await file.writeAsString(value);
    _entries.removeWhere((entry) => entry['file'] == name);
    _entries.add({'file': name, 'bytes': await file.length()});
  }

  Future<void> writeManifest() async {
    final entries = [..._entries]
      ..sort(
        (left, right) =>
            (left['file']! as String).compareTo(right['file']! as String),
      );
    final file = File('${directory.path}/manifest.json');
    await file.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({'generated_at': DateTime.now().toUtc().toIso8601String(), 'contains_credentials': false, 'contains_persisted_cookies': false, 'files': entries})}\n',
    );
  }

  String _sanitizeSessionJson(String body) {
    try {
      final decoded = jsonDecode(body);
      return '${const JsonEncoder.withIndent('  ').convert(_redactSessionTokens(decoded))}\n';
    } on FormatException {
      return body;
    }
  }

  Object? _redactSessionTokens(Object? value) {
    if (value is List) {
      return value.map(_redactSessionTokens).toList();
    }
    if (value is Map) {
      return value.map((key, item) {
        final normalizedKey = key.toString().toLowerCase();
        if (normalizedKey == 'sessiontoken') {
          return MapEntry(key, '[redacted]');
        }
        return MapEntry(key, _redactSessionTokens(item));
      });
    }
    return value;
  }
}

class ProbeRunResult {
  const ProbeRunResult({
    required this.classification,
    required this.report,
    required this.artifactDirectory,
  });

  final ProbeClassification classification;
  final String report;
  final String artifactDirectory;
}

String _safeName(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}
