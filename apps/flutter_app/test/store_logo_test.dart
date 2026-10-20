import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiago_market_app/src/models/models.dart';
import 'package:tiago_market_app/src/widgets/product_comparison_card.dart';
import 'package:tiago_market_app/src/widgets/store_logo.dart';

void main() {
  test('identifica cadenas por slug o nombre online', () {
    expect(StoreLogo.assetFor('Chedraui online'),
        'assets/store_logos/chedraui.png');
    expect(StoreLogo.assetFor('Smart & Final México online'),
        'assets/store_logos/smart-final.png');
    expect(StoreLogo.assetFor('Sucursal', storeSlug: 'home-depot-mx'),
        'assets/store_logos/home-depot.png');
    expect(StoreLogo.assetFor('Bodega Aurrerá'),
        'assets/store_logos/bodega-aurrera.png');
    expect(StoreLogo.assetFor('Comercio nuevo'), isNull);
  });
  testWidgets('un comercio desconocido mantiene su identidad accesible',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: StoreLogo(storeName: 'Comercio nuevo')));
    expect(find.byIcon(Icons.storefront_rounded), findsOneWidget);
    expect(find.byTooltip('Comercio nuevo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('muestra cada vendedor al comparar en móvil', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final group = ProductComparisonGroup(
        comparisonKey: 'leche',
        productName: 'Leche entera 1 l',
        prices: const [
          PriceResult(
              storeName: 'Chedraui online',
              productName: 'Leche entera',
              price: 20,
              capturedAt: ''),
          PriceResult(
              storeName: 'Merco online',
              productName: 'Leche entera',
              price: 22,
              capturedAt: ''),
        ]);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ProductComparisonCard(
                group: group, onAdd: () {}, favorite: false))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    expect(
        tester
            .widgetList<StoreLogo>(find.byType(StoreLogo))
            .map((logo) => logo.storeName)
            .toList(),
        ['Chedraui online', 'Chedraui online', 'Merco online']);
    expect(tester.takeException(), isNull);
  });
}
