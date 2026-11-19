import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiago_market_app/src/controllers/search_controller.dart'
    as local;
import 'package:tiago_market_app/src/models/models.dart';
import 'package:tiago_market_app/src/pages/search_page.dart';
import 'package:tiago_market_app/src/services/market_api.dart';
import 'package:tiago_market_app/src/widgets/product_comparison_card.dart';

PriceResult product(int index, {String freshness = 'fresh'}) => PriceResult(
      storeName: 'Fixture store',
      productName: 'Product ${index.toString().padLeft(4, '0')}',
      price: (index + 1).toDouble(),
      capturedAt: '',
      presentation: '1 kg',
      freshness: freshness,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a long catalog only builds cards near the viewport',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = local.SearchController(
      api: MarketApi(rpcInvoker: (_, __) async => []),
      loadOnStart: false,
    )
      ..results = List.generate(1000, product)
      ..hasMore = false;
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(home: SearchPageBody()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ProductComparisonCard), findsWidgets);
    expect(find.byType(ProductComparisonCard).evaluate().length, lessThan(12));
    expect(find.text('Product 0999'), findsNothing);
    final scrollable = find
        .descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(find.text('Product 0000'), 200,
        scrollable: scrollable);
    await tester.tap(find.text('Product 0000'));
    await tester.pumpAndSettle();
    expect(find.byType(PriceCard), findsOneWidget);

    controller.scrollController.jumpTo(7000);
    await tester.pumpAndSettle();
    expect(find.byType(ProductComparisonCard).evaluate().length, lessThan(12));
    expect(find.text('Product 0000'), findsNothing);

    controller.scrollController.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.byType(PriceCard), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('cart updates reuse grouping and filters never retain old results',
      () async {
    final controller = local.SearchController(
      api: MarketApi(rpcInvoker: (_, __) async => []),
      loadOnStart: false,
    )..results = [product(0, freshness: 'old'), product(1)];
    addTearDown(controller.dispose);
    final groups = controller.groupedResults;
    await controller.addToShoppingList(groups.first);
    expect(controller.groupedResults, same(groups));

    controller.sortMode = 'price_desc';
    expect(controller.groupedResults.first.best.price, 2);
    controller.freshOnly = true;
    expect(controller.filteredResults.single.price, 2);
    expect(controller.groupedResults.single.best.price, 2);

    controller.results = [product(2)];
    expect(controller.filteredResults.single.price, 3);
    expect(controller.groupedResults.single.best.price, 3);
    controller.freshOnly = false;
    expect(controller.groupedResults.single.best.price, 3);
  });
}
