import 'package:tiago_market_app/src/models/models.dart';
import 'package:tiago_market_app/src/services/market_api.dart';

/// Entirely fictional fixtures. No HTTP, Supabase, credentials or real stores.
class DemoMarketApi extends MarketApi {
  @override
  bool get isDemo => true;

  static const _products = [
    (
      name: 'Leche entera 1 L',
      category: 'Lácteos',
      size: '1 l',
      a: 27.5,
      b: 30.0
    ),
    (
      name: 'Arroz súper extra 900 g',
      category: 'Despensa',
      size: '900 g',
      a: 32.0,
      b: 29.5
    ),
    (
      name: 'Huevo blanco 12 piezas',
      category: 'Huevos',
      size: '12 pza',
      a: 45.0,
      b: 49.0
    ),
    (
      name: 'Pasta de fideo 200 g',
      category: 'Despensa',
      size: '200 g',
      a: 12.0,
      b: 10.5
    ),
    (
      name: 'Café molido 250 g',
      category: 'Despensa',
      size: '250 g',
      a: 68.0,
      b: 64.0
    ),
    (
      name: 'Aceite vegetal 1 L',
      category: 'Despensa',
      size: '1 l',
      a: 38.0,
      b: 42.5
    ),
    (
      name: 'Azúcar estándar 1 kg',
      category: 'Despensa',
      size: '1 kg',
      a: 28.0,
      b: 26.0
    ),
    (
      name: 'Refresco de cola 600 ml',
      category: 'Bebidas',
      size: '600 ml',
      a: 17.0,
      b: 19.5
    ),
  ];

  static List<PriceResult> get _rows => [
        for (final product in _products)
          for (final store in [
            (
              name: 'Mercado Centro · ejemplo',
              slug: 'demo-centro',
              price: product.a
            ),
            (
              name: 'Despensa Norte · ejemplo',
              slug: 'demo-norte',
              price: product.b
            ),
          ])
            PriceResult(
              productName: product.name,
              normalizedName: product.name.toLowerCase(),
              storeName: store.name,
              storeSlug: store.slug,
              price: store.price,
              presentation: product.size,
              category: product.category,
              source: 'demo',
              capturedAt: '',
            ),
      ];

  static String _normalize(String value) {
    var normalized = value.toLowerCase();
    for (final pair in [
      ('á', 'a'),
      ('é', 'e'),
      ('í', 'i'),
      ('ó', 'o'),
      ('ú', 'u'),
      ('ü', 'u')
    ]) {
      normalized = normalized.replaceAll(pair.$1, pair.$2);
    }
    return normalized;
  }

  @override
  Future<List<PriceResult>> compare(
    String query, {
    double? latitude,
    double? longitude,
    double radiusKm = 10,
    String orderBy = 'price',
    int page = 1,
    String? category,
  }) async {
    if (page != 1 || latitude != null || longitude != null) return [];
    final terms = _normalize(query)
        .replaceAll(RegExp(r'\bcoca\b'), 'cola')
        .trim()
        .split(RegExp(r'\s+'));
    final rows = _rows.where((row) {
      final text = _normalize('${row.productName} ${row.category}');
      return (category == null || row.category == category) &&
          terms.every(text.contains);
    }).toList();
    rows.sort((a, b) => orderBy == 'price_desc'
        ? b.price.compareTo(a.price)
        : a.price.compareTo(b.price));
    return rows;
  }

  @override
  Future<List<PriceResult>> onlinePrices(String query,
          {int page = 1, String? category, String orderBy = 'price_asc'}) =>
      compare(query, page: page, category: category, orderBy: orderBy);

  @override
  Future<List<ProductCategory>> categories(
          {double? latitude, double? longitude, double radiusKm = 10}) async =>
      [
        for (final name in _products.map((p) => p.category).toSet())
          ProductCategory(
            name: name,
            count: _products.where((p) => p.category == name).length,
          ),
      ];

  @override
  Future<int> nearbyBranchCount(
          double latitude, double longitude, double radiusKm) async =>
      0;

  @override
  Future<void> sendFeedback(String message) async {
    throw UnsupportedError('La demo no envía mensajes ni datos personales.');
  }
}
