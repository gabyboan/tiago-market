import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiago_market_app/src/models/checkout.dart';
import 'package:tiago_market_app/src/models/models.dart';
import 'package:tiago_market_app/src/pages/checkout_page.dart';
import 'package:tiago_market_app/src/widgets/shopping_list_sheet.dart';

PriceResult offer(
        {String? branch,
        double price = 12.35,
        bool available = true,
        String currency = 'MXN'}) =>
    PriceResult(
      storeName: 'Tienda de prueba',
      branchId: branch,
      branchName: branch,
      productName: 'Leche 1 l',
      price: price,
      available: available,
      currency: currency,
      capturedAt: '2026-10-07T12:00:00Z',
    );

ShoppingItem item(String key, List<PriceResult> prices, {int quantity = 1}) =>
    ShoppingItem(
        comparisonKey: key,
        productName: key,
        quantity: quantity,
        prices: prices);

void main() {
  test('separa sucursales y no suma cobertura de ubicaciones distintas', () {
    final baskets = buildCheckoutBaskets([
      item('leche', [offer(branch: 'A')]),
      item('pan', [offer(branch: 'B')]),
    ]);
    expect(baskets, hasLength(2));
    expect(baskets.every((basket) => !basket.isComplete), isTrue);
  });

  test('excluye ofertas no disponibles, inválidas y de otra moneda', () {
    final baskets = buildCheckoutBaskets([
      item('leche', [
        offer(available: false),
        offer(price: double.nan),
        offer(price: -1),
        offer(currency: 'USD')
      ]),
    ]);
    expect(baskets, isEmpty);
  });

  test('calcula centavos por unidad y conserva la evidencia para revalidar',
      () {
    final basket = buildCheckoutBaskets([
      item('leche', [offer(price: 20), offer()], quantity: 3),
    ]).single;
    expect(basket.isComplete, isTrue);
    expect(basket.subtotalMinor, 3705);
    expect(basket.lines.single.toJson()['unit_amount_minor'], 1235);
    expect(basket.lines.single.toJson()['offer'], contains('captured_at'));
  });

  testWidgets(
      'exige domicilio y código postal válido y permite editar el borrador',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: CheckoutPage(items: [
      item('leche', [offer()])
    ])));
    expect(find.text('Retiro en tienda'), findsNothing);
    final scroll = find.byType(Scrollable).first;
    Future<void> reveal(Finder finder) async {
      tester.state<ScrollableState>(scroll).position.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(finder, 250, scrollable: scroll);
      await tester.pumpAndSettle();
    }

    final review = find.widgetWithText(FilledButton, 'Revisar borrador');
    await reveal(review);
    await tester.tap(review);
    await tester.pumpAndSettle();
    expect(find.text('Borrador de compra'), findsNothing);
    await reveal(find.widgetWithText(TextFormField, 'Nombre y apellido'));
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre y apellido'), 'Ana Pérez');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Teléfono de contacto'),
        '5512345678');
    await reveal(
        find.widgetWithText(TextFormField, 'Calle, número e interior'));
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Calle, número e interior'),
        'Reforma 10');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Colonia'), 'Centro');
    await reveal(find.widgetWithText(TextFormField, 'Ciudad o municipio'));
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Ciudad o municipio'),
        'Ciudad de México');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Estado'), 'CDMX');
    await reveal(find.widgetWithText(TextFormField, 'Código postal de México'));
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Código postal de México'), '123');
    await reveal(review);
    await tester.tap(review);
    await tester.pumpAndSettle();
    await reveal(find.text('Ingresa los 5 dígitos del código postal'));
    expect(
        find.text('Ingresa los 5 dígitos del código postal'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Código postal de México'), '06000');
    await reveal(find.text('Transferencia bancaria'));
    await tester.tap(find.text('Transferencia bancaria'));
    await reveal(review);
    await tester.tap(review);
    await tester.pumpAndSettle();
    expect(find.text('Borrador de compra'), findsOneWidget);
    expect(find.textContaining('Retiro'), findsNothing);
    await reveal(find.text('Entrega y contacto'));
    expect(find.text('Envío a domicilio'), findsOneWidget);
    expect(find.text('Reforma 10'), findsOneWidget);
    expect(find.textContaining('CP 06000'), findsOneWidget);
    await reveal(find.text('Forma de pago elegida'));
    expect(find.text('Transferencia bancaria'), findsOneWidget);
    await reveal(find.text('Editar datos'));
    await tester.tap(find.text('Editar datos'));
    await tester.pumpAndSettle();
    await reveal(find.widgetWithText(TextFormField, 'Nombre y apellido'));
    expect(
        tester
            .widget<TextFormField>(
                find.widgetWithText(TextFormField, 'Nombre y apellido'))
            .controller!
            .text,
        'Ana Pérez');
    expect(tester.takeException(), isNull);
  });

  testWidgets('una lista parcial no permite revisar una compra',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: CheckoutPage(items: [
      item('leche', [offer()]),
      item('pan', []),
    ])));
    await tester.scrollUntilVisible(find.text('Revisar borrador'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Revisar borrador'))
            .onPressed,
        isNull);
  });

  testWidgets('la lista de compras abre la sección de envío y pago',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ShoppingListSheet(
      items: [
        item('leche', [offer()])
      ],
      onQuantityChanged: (item, quantity) async {},
    ))));
    await tester.tap(find.text('Preparar envío y pago'));
    await tester.pumpAndSettle();
    expect(find.text('Envío y métodos de pago'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
