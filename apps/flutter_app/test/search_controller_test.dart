import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiago_market_app/src/controllers/search_controller.dart';
import 'package:tiago_market_app/src/models/models.dart';
import 'package:tiago_market_app/src/services/market_api.dart';

class FakeMarketApi extends MarketApi {
  FakeMarketApi({
    this.compareResponse = const [],
    this.categoriesResponse = const [],
    this.compareByLocation,
    this.nearbyBranchCountResponse = 0,
  });

  final List<PriceResult> compareResponse;
  final List<ProductCategory> categoriesResponse;
  final List<PriceResult> Function(double? latitude, double? longitude)?
      compareByLocation;
  final int nearbyBranchCountResponse;

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
    final handler = compareByLocation;
    if (handler != null) return handler(latitude, longitude);
    return compareResponse;
  }

  @override
  Future<List<ProductCategory>> categories() async => categoriesResponse;

  @override
  Future<int> nearbyBranchCount(
    double latitude,
    double longitude,
    double radiusKm,
  ) async {
    return nearbyBranchCountResponse;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('agrega y actualiza un elemento a la lista de compras', () async {
    final api = FakeMarketApi();
    final controller = SearchController(api: api);

    await Future<void>.delayed(Duration.zero);

    expect(controller.shoppingItems, isEmpty);

    final group = ProductComparisonGroup(
      comparisonKey: 'leche|1000:ml',
      productName: 'Leche',
      prices: const [
        PriceResult(
          storeName: 'Aurrera',
          productName: 'Leche',
          normalizedName: 'leche 1 l',
          price: 45,
          capturedAt: '2026-01-01',
        ),
      ],
    );

    await controller.addToShoppingList(group);
    expect(controller.shoppingItems, hasLength(1));
    expect(controller.shoppingItems.first.quantity, 1);

    final item = controller.shoppingItems.first;
    await controller.updateShoppingItem(item, 3);
    expect(controller.shoppingItems.first.quantity, 3);

    await controller.updateShoppingItem(item, 0);
    expect(controller.shoppingItems, isEmpty);
  });

  test('realiza búsqueda con api inyectada y actualiza resultados', () async {
    final result = PriceResult(
      storeName: 'La Comer',
      productName: 'Arroz',
      normalizedName: 'arroz 1 kg',
      price: 32,
      capturedAt: '2026-01-01',
    );
    final api =
        FakeMarketApi(compareResponse: [result], categoriesResponse: const []);
    final controller = SearchController(api: api);

    await Future<void>.delayed(Duration.zero);
    controller.queryController.text = 'arroz';
    await controller.search();

    expect(controller.results, contains(result));
    expect(controller.filteredResults, contains(result));
  });

  test('usa precios online cuando la ubicacion no tiene precios por sucursal',
      () async {
    final onlineResult = PriceResult(
      storeName: 'Chedraui online',
      productName: 'Telera',
      normalizedName: 'telera',
      price: 2,
      capturedAt: '2026-01-01',
    );
    final api = FakeMarketApi(
      nearbyBranchCountResponse: 3,
      compareByLocation: (latitude, longitude) {
        return latitude == null && longitude == null ? [onlineResult] : [];
      },
    );
    final controller = SearchController(api: api)
      ..latitude = 19.43
      ..longitude = -99.13;

    await Future<void>.delayed(Duration.zero);
    await controller.searchWithLocationFallback();

    expect(controller.results, contains(onlineResult));
    expect(controller.showingOnlineFallback, isTrue);
    expect(controller.nearbyBranches, 3);
    expect(controller.error, contains('precios online'));
  });

  test('guarda historial de busqueda y borra historial', () async {
    final api = FakeMarketApi();
    final controller = SearchController(api: api);

    await Future<void>.delayed(Duration.zero);
    controller.queryController.text = 'arroz';
    await controller.search();

    expect(controller.searchHistory, contains('arroz'));

    controller.queryController.text = 'leche';
    await controller.search();
    expect(controller.searchHistory.first, 'leche');
    expect(controller.searchHistory.length, 2);

    await controller.clearSearchHistory();
    expect(controller.searchHistory, isEmpty);
  });

  test('guarda favorito y lo agrega a la lista de compras', () async {
    final api = FakeMarketApi();
    final controller = SearchController(api: api);

    await Future<void>.delayed(Duration.zero);
    expect(controller.favorites, isEmpty);

    final group = ProductComparisonGroup(
      comparisonKey: 'leche|1000:ml',
      productName: 'Leche',
      prices: const [
        PriceResult(
          storeName: 'Aurrera',
          productName: 'Leche',
          normalizedName: 'leche 1 l',
          price: 45,
          capturedAt: '2026-01-01',
        ),
      ],
    );

    await controller.toggleFavorite(group);
    expect(controller.favorites, hasLength(1));
    expect(controller.isFavorite(group), isTrue);

    final favorite = controller.favorites.first;
    await controller.addFavoriteToShoppingList(favorite);
    expect(controller.shoppingItems, hasLength(1));
    expect(controller.shoppingItems.first.quantity, 1);

    await controller.addFavoriteToShoppingList(favorite);
    expect(controller.shoppingItems.first.quantity, 2);
  });
}
