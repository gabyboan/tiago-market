import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

void main() => runApp(const TiagoMarketApp());

class TiagoMarketApp extends StatelessWidget {
  const TiagoMarketApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tiago Market',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF006C51)),
        scaffoldBackgroundColor: const Color(0xFFF5F7F5),
        useMaterial3: true,
        cardTheme: const CardThemeData(
          margin: EdgeInsets.zero,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
            side: BorderSide(color: Color(0xFFE1E8E4)),
          ),
        ),
      ),
      home: const SearchPage(),
    );
  }
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _api = MarketApi();

  List<PriceResult> _results = demoPrices;
  bool _loading = false;
  bool _usingDemo = apiBaseUrl.isEmpty;
  bool _locating = false;
  double? _latitude;
  double? _longitude;
  double _radiusKm = 10;
  String _orderBy = 'price';
  int _page = 1;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (apiBaseUrl.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search([String? quickQuery, bool append = false]) async {
    if (quickQuery != null) _controller.text = quickQuery;
    final query = _controller.text.trim();
    final page = append ? _page + 1 : 1;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await _api.compare(
        query,
        latitude: _latitude,
        longitude: _longitude,
        radiusKm: _radiusKm,
        orderBy: _orderBy,
        page: page,
      );
      if (!mounted) return;
      setState(() {
        _results = append ? [..._results, ...results] : results;
        _page = page;
        _hasMore = results.length == 50;
        _usingDemo = apiBaseUrl.isEmpty;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _results = demoPrices;
        _usingDemo = true;
        _error = 'No se pudo consultar la API. Mostrando una vista de ejemplo.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _useLocation() async {
    setState(() {
      _locating = true;
      _error = null;
    });

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Activa la ubicación del dispositivo para continuar.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('No se concedió permiso de ubicación.');
      }

      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _orderBy = 'distance';
      });
      await _search();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _clearLocation() {
    setState(() {
      _latitude = null;
      _longitude = null;
      _orderBy = 'price';
    });
    _search();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F7F5),
        title: const Row(
          children: [
            CircleAvatar(
              backgroundColor: Color(0xFF006C51),
              foregroundColor: Colors.white,
              child: Icon(Icons.shopping_basket_rounded),
            ),
            SizedBox(width: 12),
            Text('Tiago Market', style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
              children: [
                const Text(
                  'Compara antes\nde comprar.',
                  style: TextStyle(
                    fontSize: 36,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Explora el catálogo observado por PROFECO o busca un producto.',
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                SearchBar(
                  controller: _controller,
                  hintText: 'Busca leche, arroz, huevo...',
                  leading: const Icon(Icons.search_rounded),
                  trailing: [
                    IconButton(
                      onPressed: _loading ? null : _search,
                      icon: const Icon(Icons.arrow_forward_rounded),
                    ),
                  ],
                  onSubmitted: (_) => _search(),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final query in ['coca', 'leche', 'arroz', 'huevo'])
                      ActionChip(
                        label: Text(query),
                        onPressed: _loading ? null : () => _search(query),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _locating ? null : _useLocation,
                      icon: _locating
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location_rounded),
                      label: Text(
                        _latitude == null
                            ? 'Usar mi ubicación'
                            : 'Ubicación activa',
                      ),
                    ),
                    if (_latitude != null)
                      ActionChip(
                        avatar: const Icon(Icons.close_rounded, size: 18),
                        label: const Text('Quitar ubicación'),
                        onPressed: _clearLocation,
                      ),
                    DropdownButton<double>(
                      value: _radiusKm,
                      items: [2, 5, 10, 20]
                          .map(
                            (radius) => DropdownMenuItem(
                              value: radius.toDouble(),
                              child: Text('$radius km'),
                            ),
                          )
                          .toList(),
                      onChanged: _latitude == null
                          ? null
                          : (value) {
                              if (value == null) return;
                              setState(() => _radiusKm = value);
                              _search();
                            },
                    ),
                    DropdownButton<String>(
                      value: _orderBy,
                      items: const [
                        DropdownMenuItem(
                          value: 'price',
                          child: Text('Menor precio'),
                        ),
                        DropdownMenuItem(
                          value: 'distance',
                          child: Text('Más cerca'),
                        ),
                      ],
                      onChanged: _latitude == null
                          ? null
                          : (value) {
                              if (value == null) return;
                              setState(() => _orderBy = value);
                              _search();
                            },
                    ),
                  ],
                ),
                if (_latitude != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Buscando dentro de ${_radiusKm.toStringAsFixed(0)} km. '
                    'Tu ubicación se usa solo para esta consulta.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                if (_usingDemo)
                  const _Notice(
                    icon: Icons.science_outlined,
                    text:
                        'Vista demo. Al desplegar la API, esta pantalla mostrará datos en vivo.',
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  _Notice(icon: Icons.info_outline, text: _error!),
                ],
                const SizedBox(height: 22),
                Row(
                  children: [
                    Text(
                      'Mejores precios',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_results.length} resultados',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_results.isEmpty)
                  const _EmptyState()
                else
                  for (final result in _results) ...[
                    PriceCard(result: result),
                    const SizedBox(height: 12),
                  ],
                if (!_loading && _hasMore && !_usingDemo)
                  OutlinedButton.icon(
                    onPressed: () => _search(null, true),
                    icon: const Icon(Icons.expand_more_rounded),
                    label: const Text('Cargar otros 50 precios'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PriceCard extends StatelessWidget {
  const PriceCard({required this.result, super.key});

  final PriceResult result;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: const Color(0xFFE2F3EB),
              foregroundColor: const Color(0xFF006C51),
              child: Text(
                result.storeName.substring(0, 1),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.storeName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    result.productName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Sucursal: ${result.branchName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    result.observationLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (result.distanceKm != null)
                    Text(
                      '${result.distanceKm!.toStringAsFixed(1)} km de distancia',
                      style: const TextStyle(
                        color: Color(0xFF006C51),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (result.observationUrl != null)
                        TextButton.icon(
                          onPressed: () => _openUrl(result.observationUrl!),
                          icon: const Icon(Icons.fact_check_outlined, size: 17),
                          label: const Text('Ver observación PROFECO'),
                        ),
                      if (result.storeProductUrl != null)
                        TextButton.icon(
                          onPressed: () => _openUrl(result.storeProductUrl!),
                          icon: const Icon(Icons.open_in_new_rounded, size: 17),
                          label: const Text('Ver en la tienda'),
                        ),
                    ],
                  ),
                  if (result.freshness == 'old') ...[
                    const SizedBox(height: 6),
                    const Text(
                      'Este precio puede estar desactualizado.',
                      style: TextStyle(
                        color: Color(0xFF9A3412),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '\$${result.price.toStringAsFixed(2)}',
              style: const TextStyle(
                color: Color(0xFF006C51),
                fontSize: 23,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openUrl(String value) async {
    final uri = Uri.tryParse(value);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4D8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 44),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, size: 44),
          SizedBox(height: 10),
          Text('No encontramos precios para esa búsqueda.'),
        ],
      ),
    );
  }
}

class MarketApi {
  Future<List<PriceResult>> compare(
    String query, {
    double? latitude,
    double? longitude,
    double radiusKm = 10,
    String orderBy = 'price',
    int page = 1,
  }) async {
    if (apiBaseUrl.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 450));
      return demoPricesFor(query);
    }

    final uri = Uri.parse('$apiBaseUrl/api/v1/compare').replace(
      queryParameters: {
        'query': query,
        'limit': '50',
        'page': page.toString(),
        if (query.trim().isNotEmpty) 'query': query,
        if (query.trim().isNotEmpty &&
            latitude != null &&
            longitude != null) ...{
          'lat': latitude.toString(),
          'lng': longitude.toString(),
          'radius_km': radiusKm.toString(),
          'order_by': orderBy,
        },
      },
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('API respondió ${response.statusCode}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final data = body['data'] as List<dynamic>? ?? [];
    return data
        .map((item) => PriceResult.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}

class PriceResult {
  const PriceResult({
    required this.storeName,
    required this.productName,
    required this.branchName,
    required this.price,
    required this.capturedAt,
    this.source = 'profeco',
    this.freshness = 'fresh',
    this.daysOld = 0,
    this.distanceKm,
    this.observationUrl,
    this.storeProductUrl,
  });

  factory PriceResult.fromJson(Map<String, dynamic> json) {
    return PriceResult(
      storeName: json['store_name'] as String? ?? 'Tienda',
      productName: json['product_name'] as String? ?? 'Producto',
      branchName: json['branch_name'] as String? ?? 'Sucursal no informada',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      source: json['source'] as String? ?? 'fuente no informada',
      capturedAt: json['captured_at'] as String? ?? '',
      freshness: json['freshness'] as String? ?? 'old',
      daysOld: (json['days_old'] as num?)?.toInt() ?? 0,
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
      observationUrl: json['observation_url'] as String?,
      storeProductUrl: json['store_product_url'] as String?,
    );
  }

  final String storeName;
  final String productName;
  final String branchName;
  final double price;
  final String source;
  final String capturedAt;
  final String freshness;
  final int daysOld;
  final double? distanceKm;
  final String? observationUrl;
  final String? storeProductUrl;

  String get observationLabel {
    final age = daysOld == 1 ? 'hace 1 día' : 'hace $daysOld días';
    return 'Precio observado por ${source.toUpperCase()} · $age';
  }
}

const demoPrices = [
  PriceResult(
    storeName: 'BODEGA AURRERA',
    productName: 'REFRESCO, COCA COLA, BOTELLA 600 ML. SIN AZÚCAR',
    branchName: 'Iztapalapa',
    price: 15,
    capturedAt: '2026-06-09T12:00:00.000Z',
    daysOld: 2,
    distanceKm: 1.8,
    observationUrl: 'https://qqp.profeco.gob.mx/results',
  ),
  PriceResult(
    storeName: 'MERCADO SORIANA',
    productName: 'REFRESCO, COCA COLA, BOTELLA 600 ML. SIN AZÚCAR',
    branchName: 'San Lorenzo Xalpa',
    price: 16,
    capturedAt: '2026-06-09T12:00:00.000Z',
    daysOld: 2,
    distanceKm: 3.4,
    observationUrl: 'https://qqp.profeco.gob.mx/results',
  ),
  PriceResult(
    storeName: 'WAL-MART',
    productName: 'REFRESCO, COCA COLA, BOTELLA 600 ML. SIN AZÚCAR',
    branchName: 'Lomas',
    price: 17.5,
    capturedAt: '2026-06-09T12:00:00.000Z',
    daysOld: 2,
    distanceKm: 5.1,
    observationUrl: 'https://qqp.profeco.gob.mx/results',
  ),
];

List<PriceResult> demoPricesFor(String query) {
  final normalized = query.toLowerCase();
  if (normalized.contains('leche')) return demoMilkPrices;
  if (normalized.contains('arroz')) return demoRicePrices;
  if (normalized.contains('huevo')) return demoEggPrices;
  return demoPrices;
}

const demoMilkPrices = [
  PriceResult(
    storeName: 'HIPERMERCADO SORIANA',
    productName: 'LECHE ULTRAPASTEURIZADA, VALLEY FOODS, BOLSA 1 LT. ENTERA',
    branchName: 'Mixcoac',
    price: 14.9,
    capturedAt: '2026-06-09T12:00:00.000Z',
    daysOld: 2,
  ),
  PriceResult(
    storeName: 'BODEGA AURRERA',
    productName: 'LECHE ULTRAPASTEURIZADA, GREAT VALUE, CAJA 1 LT. ENTERA',
    branchName: 'Tacubaya',
    price: 19,
    capturedAt: '2026-06-09T12:00:00.000Z',
    daysOld: 2,
  ),
];

const demoRicePrices = [
  PriceResult(
    storeName: 'WAL-MART',
    productName: 'ARROZ, SOS, BOLSA 1 KG. SUPER EXTRA. INTEGRAL',
    branchName: 'Universidad',
    price: 33,
    capturedAt: '2026-06-08T12:00:00.000Z',
    daysOld: 3,
  ),
  PriceResult(
    storeName: 'BODEGA AURRERA',
    productName: 'ARROZ, VERDE VALLE, BOLSA 1 KG. SUPER EXTRA',
    branchName: 'Tacubaya',
    price: 37,
    capturedAt: '2026-06-09T12:00:00.000Z',
    daysOld: 2,
  ),
];

const demoEggPrices = [
  PriceResult(
    storeName: 'BODEGA AURRERA',
    productName: 'HUEVO, AURRERA, PAQUETE C/12. BLANCO',
    branchName: 'Iztapalapa',
    price: 35,
    capturedAt: '2026-06-09T12:00:00.000Z',
    daysOld: 2,
  ),
  PriceResult(
    storeName: 'MEGA SORIANA',
    productName: 'HUEVO, EL CALVARIO, PAQUETE CON 12 BLANCO',
    branchName: 'Tacuba',
    price: 42.9,
    capturedAt: '2026-06-09T12:00:00.000Z',
    daysOld: 2,
  ),
];
