import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiago_market_app/src/app.dart';
import 'package:tiago_market_app/src/controllers/search_controller.dart'
    as local;
import 'package:tiago_market_app/src/demo/demo_market_api.dart';
import 'package:tiago_market_app/src/pages/search_page.dart';
import 'package:tiago_market_app/src/widgets/shopping_list_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('fixtures ficticios, búsqueda, categorías y separación de sucursales',
      () async {
    final api = DemoMarketApi();
    final all = await api.compare('');
    expect(all.length, 16);
    expect(
        all.every((p) =>
            p.source == 'demo' &&
            p.storeSlug!.startsWith('demo-') &&
            p.capturedAt.isEmpty &&
            p.storeProductUrl == null &&
            p.imageUrl == null),
        isTrue);
    expect((await api.compare('LECHE')).length, 2);
    expect((await api.compare('coca')).length, 2);
    expect((await api.compare('cafe')).length, 2);
    expect((await api.compare('', category: 'Despensa')).length, 10);
    expect(await api.compare('', page: 2), isEmpty);
    expect(await api.compare('', latitude: 19.4, longitude: -99.1), isEmpty);
    expect(await api.compare('producto inexistente'), isEmpty);
    expect(api.sendFeedback('fixture'), throwsUnsupportedError);
  });

  for (final textScale in [1.0, 1.8]) {
    testWidgets(
        'demo sin login y carrito sin datos personales, texto $textScale',
        (tester) async {
      tester.view.physicalSize = const Size(340, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(TiagoMarketApp(marketApi: DemoMarketApi()));
      await tester.pumpAndSettle();
      expect(find.textContaining('Demo · datos ficticios'), findsOneWidget);
      expect(find.text('Continuar con Google'), findsNothing);
      expect(find.text('Buscar por ubicación'), findsNothing);
      final toolbar = tester.getRect(find.byType(AppBar));
      for (final label in ['Favoritos', 'Lista de compras', 'Aviso legal']) {
        final button = tester.getRect(find.byTooltip(label));
        expect(button.top, greaterThanOrEqualTo(toolbar.top));
        expect(button.bottom, lessThanOrEqualTo(toolbar.bottom));
      }
      expect(toolbar.height, kToolbarHeight);
      final controller = tester
          .element(find.byType(SearchPage))
          .read<local.SearchController>();
      expect(controller.usingDemo, isTrue);
      await controller.submitSearch(quickQuery: 'leche');
      await tester.pumpAndSettle();
      expect(controller.groupedResults.length, 1);
      await controller.addToShoppingList(controller.groupedResults.single);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Lista de compras'));
      await tester.pumpAndSettle();
      expect(find.text('Mi lista de compras'), findsOneWidget);
      final sheetScroll = find
          .descendant(
              of: find.byType(ShoppingListSheet),
              matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('shopping-list-estimate')), 160,
          scrollable: sheetScroll);

      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('shopping-list-estimate')))
            .data,
        '\$27.50',
      );
      await tester.scrollUntilVisible(
          find.textContaining('Demo: no se crean pedidos'), 160,
          scrollable: sheetScroll);
      expect(find.textContaining('Demo: no se crean pedidos'), findsOneWidget);
      expect(find.text('Preparar envío y pago'), findsNothing);
      expect(
          find.descendant(
              of: find.byType(ShoppingListSheet),
              matching: find.byType(TextField)),
          findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
