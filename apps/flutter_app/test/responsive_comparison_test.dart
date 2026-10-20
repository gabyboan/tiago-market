import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiago_market_app/src/models/models.dart';
import 'package:tiago_market_app/src/widgets/product_comparison_card.dart';

void main() {
  const name = 'Arroz para sushi Verde Valle presentación familiar 1 kg';
  const store = 'Smart & Final México catálogo online';
  const detail = 'Precios online, no verificados para una sucursal cercana.';
  for (final size in [
    (320.0, 1.0),
    (340.0, .86),
    (340.0, 1.6),
    (360.0, 2.0),
    (720.0, 1.8)
  ]) {
    testWidgets(
        'lee producto, comercio y precio con ancho ${size.$1} y texto ${size.$2}',
        (tester) async {
      tester.view.physicalSize = Size(size.$1, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var adds = 0;
      var favorites = 0;
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(size.$2)),
          child: child!,
        ),
        home: Scaffold(
            body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ProductComparisonCard(
            group: ProductComparisonGroup(
                comparisonKey: 'fixture-rice',
                productName: name,
                prices: const [
                  PriceResult(
                      storeName: store,
                      productName: name,
                      price: 1234.56,
                      presentation: '1 kg',
                      capturedAt: '2026-10-13T12:00:00Z')
                ]),
            favorite: false,
            onAdd: () => adds++,
            onToggleFavorite: () => favorites++,
          ),
        )),
      ));
      await tester.pumpAndSettle();
      final add = tester.getCenter(find.byTooltip('Agregar a mi lista'));
      final favorite = tester.getCenter(find.byTooltip('Agregar a favoritos'));
      final title = tester.getRect(find.text(name));
      expect(add.dy, favorite.dy);
      expect(add.dx, greaterThan(title.right));
      expect(tester.takeException(), isNull);

      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
      expect(
          tester
              .renderObject<RenderParagraph>(find.text(name).last)
              .didExceedMaxLines,
          isFalse);
      expect(
          tester
              .renderObject<RenderParagraph>(find.text(store))
              .didExceedMaxLines,
          isFalse);
      expect(
          tester
              .renderObject<RenderParagraph>(find.text(detail))
              .didExceedMaxLines,
          isFalse);
      expect(find.text('\$1234.56 MXN'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.byTooltip('Agregar a mi lista'));
      await tester.tap(find.byTooltip('Agregar a mi lista'));
      await tester.tap(find.byTooltip('Agregar a favoritos'));
      expect(adds, 1);
      expect(favorites, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
