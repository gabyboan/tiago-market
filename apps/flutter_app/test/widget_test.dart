import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiago_market_app/main.dart';

void main() {
  testWidgets('muestra bienvenida antes de iniciar sesión', (tester) async {
    await tester.pumpWidget(const TiagoMarketApp());

    expect(find.text('Tu compra merece\nun mejor precio.'), findsOneWidget);
    expect(find.textContaining('Tiago Market compara precios'), findsOneWidget);
    expect(find.text('Mejores precios'), findsNothing);
    expect(find.text('BODEGA AURRERA'), findsNothing);
  });

  testWidgets('muestra ingreso breve al restaurar una cuenta', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SessionLoadingPage(returningUser: true)),
    );

    expect(find.text('Ingresando con tu cuenta de Google...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
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
