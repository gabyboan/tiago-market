import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiago_market_app/src/app.dart';
import 'package:tiago_market_app/src/models/models.dart';
import 'package:tiago_market_app/src/pages/search_page.dart';
import 'package:tiago_market_app/src/pages/welcome_page.dart';
import 'package:tiago_market_app/src/widgets/product_comparison_card.dart';
import 'package:tiago_market_app/src/widgets/shopping_list_sheet.dart';
import 'package:tiago_market_app/src/widgets/session_loading_page.dart';

void main() {
  testWidgets('ofrece Google y acceso invitado antes de abrir el catálogo',
      (tester) async {
    await tester.pumpWidget(const TiagoMarketApp());
    await tester.pumpAndSettle();
    expect(find.byType(WelcomePage), findsOneWidget);
    expect(find.text('Continuar con Google'), findsOneWidget);
    expect(find.text('Continuar sin cuenta'), findsOneWidget);
    expect(find.byType(SearchPage), findsNothing);

    await tester.tap(find.text('Continuar sin cuenta'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchPage), findsOneWidget);
    expect(find.text('Buscar por ubicación'), findsOneWidget);
    expect(find.textContaining('Catálogo online'), findsOneWidget);
    expect(find.text('Continuar sin cuenta'), findsNothing);
  });

  testWidgets('muestra ingreso breve al restaurar una cuenta', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SessionLoadingPage(returningUser: true)),
    );

    expect(find.text('Ingresando con tu cuenta de Google...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('muestra el detalle al abrir un producto con un solo precio',
      (tester) async {
    final group = ProductComparisonGroup(
      comparisonKey: 'telera',
      productName: 'Telera',
      prices: const [
        PriceResult(
          storeName: 'Chedraui online',
          productName: 'Telera',
          price: 2,
          capturedAt: '',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: Scaffold(
          body: ProductComparisonCard(
            group: group,
            onAdd: () {},
            favorite: false,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();

    expect(
      find.text('Precios online, no verificados para una sucursal cercana.'),
      findsOneWidget,
    );
    expect(find.textContaining('\$2.00'), findsNWidgets(2));
  });

  testWidgets('muestra totales interpolados en la lista de compras',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: Scaffold(
          body: ShoppingListSheet(
            items: const [
              ShoppingItem(
                comparisonKey: 'leche',
                productName: 'Leche',
                quantity: 2,
                prices: [
                  PriceResult(
                    storeName: 'Tienda A',
                    productName: 'Leche',
                    price: 20,
                    capturedAt: '',
                  ),
                ],
              ),
            ],
            onQuantityChanged: (_, __) async {},
          ),
        ),
      ),
    );

    expect(find.text('\$40.00'), findsNWidgets(2));
    expect(find.textContaining('toStringAsFixed'), findsNothing);
  });

  testWidgets('permite eliminar un producto desde la hoja de lista',
      (tester) async {
    final item = ShoppingItem(
      comparisonKey: 'leche',
      productName: 'Leche',
      quantity: 1,
      prices: const [
        PriceResult(
          storeName: 'Tienda A',
          productName: 'Leche',
          price: 20,
          capturedAt: '',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShoppingListSheet(
            items: [item],
            onQuantityChanged: (_, __) async {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Leche'), findsOneWidget);

    await tester.tap(find.byTooltip('Eliminar producto'));
    await tester.pumpAndSettle();

    expect(find.text('Leche'), findsNothing);
    expect(find.text('Tu lista está vacía'), findsOneWidget);
    expect(find.text('Leche eliminado de la lista.'), findsOneWidget);
  });

  testWidgets('vacía la lista de compras desde la hoja', (tester) async {
    final item = ShoppingItem(
      comparisonKey: 'leche',
      productName: 'Leche',
      quantity: 1,
      prices: const [
        PriceResult(
          storeName: 'Tienda A',
          productName: 'Leche',
          price: 20,
          capturedAt: '',
        ),
      ],
    );
    var updated = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShoppingListSheet(
            items: [item],
            onQuantityChanged: (_, __) async {
              updated = true;
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Leche'), findsOneWidget);

    await tester.tap(find.text('Vaciar lista'));
    await tester.pumpAndSettle();

    expect(updated, isTrue);
    expect(find.text('Tu lista está vacía'), findsOneWidget);
  });

  testWidgets('deshabilita compartir y vaciar cuando la lista está vacía',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShoppingListSheet(
            items: const [],
            onQuantityChanged: (_, __) async {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final shareButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Compartir lista'),
    );
    final clearButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Vaciar lista'),
    );

    expect(shareButton.onPressed, isNull);
    expect(clearButton.onPressed, isNull);
  });

  test('agrupa precios del mismo producto y ordena el menor primero', () {
    final groups = groupPriceResults([
      const PriceResult(
        storeName: 'Tienda B',
        productName: 'Leche entera',
        normalizedName: 'leche entera 1 l',
        price: 40,
        capturedAt: '',
      ),
      const PriceResult(
        storeName: 'Tienda A',
        productName: 'Leche entera',
        normalizedName: 'leche entera 1 l',
        price: 35,
        capturedAt: '',
      ),
    ]);

    expect(groups, hasLength(1));
    expect(groups.first.best.price, 35);
    expect(groups.first.prices, hasLength(2));
  });

  test('no agrupa presentaciones diferentes', () {
    final groups = groupPriceResults([
      const PriceResult(
        storeName: 'Tienda',
        productName: 'Leche entera',
        normalizedName: 'leche entera',
        presentation: '1 l',
        price: 35,
        capturedAt: '',
      ),
      const PriceResult(
        storeName: 'Tienda',
        productName: 'Leche entera',
        normalizedName: 'leche entera',
        presentation: '2 l',
        price: 60,
        capturedAt: '',
      ),
    ]);

    expect(groups, hasLength(2));
  });

  test('ordena grupos por mayor precio disponible', () {
    final groups = groupPriceResults([
      const PriceResult(
        storeName: 'Tienda A',
        productName: 'Leche',
        normalizedName: 'leche',
        price: 20,
        capturedAt: '',
      ),
      const PriceResult(
        storeName: 'Tienda B',
        productName: 'Arroz',
        normalizedName: 'arroz',
        price: 30,
        capturedAt: '',
      ),
    ], sortMode: 'price_desc');

    expect(groups.first.productName, 'Arroz');
  });

  test('ordena grupos por mas tiendas', () {
    final groups = groupPriceResults([
      const PriceResult(
        storeName: 'Tienda A',
        productName: 'Leche',
        normalizedName: 'leche',
        price: 20,
        capturedAt: '',
      ),
      const PriceResult(
        storeName: 'Tienda B',
        productName: 'Leche',
        normalizedName: 'leche',
        price: 22,
        capturedAt: '',
      ),
      const PriceResult(
        storeName: 'Tienda C',
        productName: 'Arroz',
        normalizedName: 'arroz',
        price: 18,
        capturedAt: '',
      ),
    ], sortMode: 'stores_desc');

    expect(groups.first.productName, 'Leche');
  });

  test('ordena precios cercanos por distancia dentro del producto', () {
    final groups = groupPriceResults([
      const PriceResult(
        storeName: 'Tienda lejos',
        productName: 'Arroz',
        normalizedName: 'arroz',
        price: 20,
        distanceKm: 8,
        capturedAt: '',
      ),
      const PriceResult(
        storeName: 'Tienda cerca',
        productName: 'Arroz',
        normalizedName: 'arroz',
        price: 24,
        distanceKm: 1.2,
        capturedAt: '',
      ),
    ], sortMode: 'distance');

    expect(groups.first.best.storeName, 'Tienda cerca');
  });

  test('calcula el total de lista por tienda y cantidad', () {
    final totals = calculateStoreTotals([
      const ShoppingItem(
        comparisonKey: 'leche|1000:ml',
        productName: 'Leche',
        quantity: 2,
        prices: [
          PriceResult(
            storeName: 'Tienda A',
            productName: 'Leche',
            price: 20,
            capturedAt: '',
          ),
          PriceResult(
            storeName: 'Tienda B',
            productName: 'Leche',
            price: 25,
            capturedAt: '',
          ),
        ],
      ),
    ]);

    expect(totals.first.storeName, 'Tienda A');
    expect(totals.first.total, 40);
  });
}
