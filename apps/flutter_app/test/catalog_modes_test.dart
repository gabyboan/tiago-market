import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiago_market_app/src/controllers/search_controller.dart';
import 'package:tiago_market_app/src/models/models.dart';
import 'package:tiago_market_app/src/services/market_api.dart';

Map<String, dynamic> row(int i, {bool local = false}) => {
      'store_name': 'Fixture store',
      'store_slug': 'fixture',
      'product_name': 'Product $i',
      'price': 10,
      'currency': 'MXN',
      'available': true,
      'source': 'fixture',
      'presentation': '1 kg',
      'captured_at': DateTime.now().toUtc().toIso8601String(),
      'freshness': 'fresh',
      'store_product_url': 'https://example.org/$i',
      if (local) ...{
        'branch_id': 'branch',
        'branch_name': 'Centro',
        'branch_address': 'Address'
      },
    };

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('startup uses online RPC without GPS; pages and categories reach RPC',
      () async {
    final calls = <(String, Map<String, dynamic>)>[];
    final api = MarketApi(rpcInvoker: (name, params) async {
      calls.add((name, params));
      if (name == 'catalog_categories_v3') return [];
      if (params['page_number'] == 1) return List.generate(100, row);
      return [row(100)];
    });
    final controller = SearchController(api: api, loadOnStart: true);
    await Future<void>.delayed(Duration.zero);
    expect(controller.hasLocation, isFalse);
    expect(calls.where((c) => c.$1 == 'nearby_prices_v4'), isEmpty);
    expect(controller.results.length, 100);
    await controller.search(append: true);
    expect(controller.results.length, 101);
    expect(controller.hasMore, isFalse);
    expect(calls.last.$2['page_number'], 2);
    controller.setCategory('Food');
    await Future<void>.delayed(Duration.zero);
    expect(calls.last.$2['category_filter'], 'Food');
    expect(calls.last.$2['page_number'], 1);
    controller.dispose();
  });

  test('local RPC receives paging/category and rejects online rows', () async {
    late Map<String, dynamic> parameters;
    final api = MarketApi(rpcInvoker: (name, params) async {
      expect(name, 'nearby_prices_v4');
      parameters = params;
      return [row(1), row(2, local: true)];
    });
    final rows = await api.compare('',
        latitude: 19.43, longitude: -99.13, page: 2, category: 'Food');
    expect(parameters['page_number'], 2);
    expect(parameters['category_filter'], 'Food');
    expect(rows.single.branchId, 'branch');
  });

  test('online rejects local, expired, invalid URL and missing presentation',
      () async {
    final api = MarketApi(
        rpcInvoker: (name, params) async => [
              row(1, local: true),
              {...row(2), 'captured_at': '2026-06-01T00:00:00Z'},
              {...row(3), 'store_product_url': 'javascript:bad'},
              {...row(4), 'presentation': null},
              row(5),
            ]);
    expect((await api.compare('')).single.productName, 'Product 5');
  });

  test('older in-flight local response cannot replace online results',
      () async {
    final pending = Completer<List<dynamic>>();
    final api = MarketApi(rpcInvoker: (name, _) async {
      if (name == 'catalog_categories_v3') return [];
      if (name == 'nearby_prices_v4') return pending.future;
      return [row(1)];
    });
    final controller = SearchController(api: api, loadOnStart: false)
      ..latitude = 19.43
      ..longitude = -99.13;
    final localRequest = controller.search();
    controller.clearLocation();
    await Future<void>.delayed(Duration.zero);
    pending.complete([row(2, local: true)]);
    await localRequest;
    expect(controller.results.single.productName, 'Product 1');
    expect(controller.results.single.branchId, isNull);
    controller.dispose();
  });

  test('date label retains exact UTC observation, not current/added date', () {
    final price = PriceResult.fromJson(
        {...row(1), 'captured_at': '2026-09-21T13:25:00Z'});
    expect(price.observationLabel, contains('2026-09-21 13:25 UTC'));
  });
}
