import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiago_market_app/src/demo/demo_market_api.dart';
import 'package:tiago_market_app/src/models/models.dart';
import 'package:tiago_market_app/src/widgets/favorites_sheet.dart';
import 'package:tiago_market_app/src/widgets/product_comparison_card.dart';
import 'package:tiago_market_app/src/widgets/product_thumbnail.dart';
import 'package:tiago_market_app/src/widgets/store_logo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('los comercios del catálogo vigente tienen logos locales válidos',
      () async {
    for (final store in [
      'COMPRO Súper · online',
      'Merkabastos · online',
      'Garís · online',
      'MAS Bodega · online',
      'CarneMart México · online',
      'Gran Bodega · online',
      'Jüsto · online',
      'Scorpion · online',
      'Chedraui',
      'Merco Monterrey',
      'Merco Nueva Rosita · online',
      'Smart & Final México · online'
    ]) {
      final asset = StoreLogo.assetFor(store);
      expect(asset, isNotNull, reason: store);
      final data = await rootBundle.load(asset!);
      final codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      final frame = await codec.getNextFrame();
      expect(frame.image.width, greaterThan(0), reason: store);
      frame.image.dispose();
      codec.dispose();
    }
  });

  testWidgets('un producto sin foto muestra el logo del comercio',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: SizedBox.square(
            dimension: 58,
            child: ProductThumbnail(
                imageUrl: null,
                productName: 'Producto',
                storeName: 'COMPRO Súper · online'))));
    await tester.pumpAndSettle();
    expect(find.image(const AssetImage('assets/store_logos/compro.png')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('los ocho productos y sus vendedores incluyen imágenes válidas',
      () async {
    final rows = await DemoMarketApi().compare('');
    final photos = rows.map((row) => row.imageUrl).toSet();
    expect(photos, hasLength(8));
    final logos = rows
        .map((row) =>
            StoreLogo.assetFor(row.storeName, storeSlug: row.storeSlug))
        .toSet();
    expect(logos, hasLength(2));
    expect(logos, isNot(contains(null)));
    for (final asset in {...photos, ...logos}) {
      final data = await rootBundle.load(asset!);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      ));
      final frame = await codec.getNextFrame();
      expect(frame.image.width, greaterThan(0), reason: asset);
      expect(frame.image.height, greaterThan(0), reason: asset);
      frame.image.dispose();
      codec.dispose();
    }
  });

  testWidgets('resultados y favoritos usan la misma foto local del producto',
      (tester) async {
    final rows = await DemoMarketApi().compare('leche');
    final group = ProductComparisonGroup(
      comparisonKey: 'demo-milk',
      productName: rows.first.productName,
      prices: rows,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProductComparisonCard(
          group: group,
          onAdd: () {},
          favorite: false,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    const photo = AssetImage('assets/demo_products/milk.jpg');
    expect(find.image(photo), findsOneWidget);
    expect(
      find.image(const AssetImage('assets/store_logos/arteli.png')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    final favorite = FavoriteItem.fromGroup(group);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FavoritesSheet(
          items: [favorite],
          onRemove: (_) async {},
          onAdd: (_) async {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.image(photo), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
