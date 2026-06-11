import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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
  final _controller = TextEditingController(text: 'coca');
  final _api = MarketApi();

  List<PriceResult> _results = demoPrices;
  bool _loading = false;
  bool _usingDemo = apiBaseUrl.isEmpty;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search([String? quickQuery]) async {
    if (quickQuery != null) _controller.text = quickQuery;
    final query = _controller.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await _api.compare(query);
      if (!mounted) return;
      setState(() {
        _results = results;
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
                  'Precios observados por PROFECO, ordenados de menor a mayor.',
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
                    'PROFECO · ${result.updatedAt}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
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
  Future<List<PriceResult>> compare(String query) async {
    if (apiBaseUrl.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 450));
      return demoPricesFor(query);
    }

    final uri = Uri.parse(
      '$apiBaseUrl/api/v1/compare',
    ).replace(queryParameters: {'query': query, 'limit': '20'});
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
    required this.updatedAt,
  });

  factory PriceResult.fromJson(Map<String, dynamic> json) {
    final externalName = json['external_name'] as String? ?? '';
    final parts = externalName.split(' · ');

    return PriceResult(
      storeName: json['store_name'] as String? ?? 'Tienda',
      productName: parts.first,
      branchName: parts.length > 1 ? parts.last : 'Sucursal no informada',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      updatedAt: _shortDate(json['last_updated_at'] as String?),
    );
  }

  final String storeName;
  final String productName;
  final String branchName;
  final double price;
  final String updatedAt;

  static String _shortDate(String? value) {
    final date = DateTime.tryParse(value ?? '');
    if (date == null) return 'fecha no informada';
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}

const demoPrices = [
  PriceResult(
    storeName: 'BODEGA AURRERA',
    productName: 'REFRESCO, COCA COLA, BOTELLA 600 ML. SIN AZÚCAR',
    branchName: 'Iztapalapa',
    price: 15,
    updatedAt: '09/06/2026',
  ),
  PriceResult(
    storeName: 'MERCADO SORIANA',
    productName: 'REFRESCO, COCA COLA, BOTELLA 600 ML. SIN AZÚCAR',
    branchName: 'San Lorenzo Xalpa',
    price: 16,
    updatedAt: '09/06/2026',
  ),
  PriceResult(
    storeName: 'WAL-MART',
    productName: 'REFRESCO, COCA COLA, BOTELLA 600 ML. SIN AZÚCAR',
    branchName: 'Lomas',
    price: 17.5,
    updatedAt: '09/06/2026',
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
    updatedAt: '09/06/2026',
  ),
  PriceResult(
    storeName: 'BODEGA AURRERA',
    productName: 'LECHE ULTRAPASTEURIZADA, GREAT VALUE, CAJA 1 LT. ENTERA',
    branchName: 'Tacubaya',
    price: 19,
    updatedAt: '09/06/2026',
  ),
];

const demoRicePrices = [
  PriceResult(
    storeName: 'WAL-MART',
    productName: 'ARROZ, SOS, BOLSA 1 KG. SUPER EXTRA. INTEGRAL',
    branchName: 'Universidad',
    price: 33,
    updatedAt: '08/06/2026',
  ),
  PriceResult(
    storeName: 'BODEGA AURRERA',
    productName: 'ARROZ, VERDE VALLE, BOLSA 1 KG. SUPER EXTRA',
    branchName: 'Tacubaya',
    price: 37,
    updatedAt: '09/06/2026',
  ),
];

const demoEggPrices = [
  PriceResult(
    storeName: 'BODEGA AURRERA',
    productName: 'HUEVO, AURRERA, PAQUETE C/12. BLANCO',
    branchName: 'Iztapalapa',
    price: 35,
    updatedAt: '09/06/2026',
  ),
  PriceResult(
    storeName: 'MEGA SORIANA',
    productName: 'HUEVO, EL CALVARIO, PAQUETE CON 12 BLANCO',
    branchName: 'Tacuba',
    price: 42.9,
    updatedAt: '09/06/2026',
  ),
];
