import 'package:flutter_test/flutter_test.dart';
import 'package:tiago_market_app/src/models/models.dart';

PriceResult price(String name, String store,
        {String? key = 'reviewed:lala-fresca-entera-carton-1l',
        String pack = '1 l',
        String currency = 'MXN',
        double amount = 34}) =>
    PriceResult.fromJson({
      'product_name': name,
      'normalized_name': name.toLowerCase(),
      'store_name': store,
      'store_slug': store,
      'source': store,
      'presentation': pack,
      'price': amount,
      'currency': currency,
      'available': true,
      'canonical_variant_key': key,
    });

void main() {
  test('reviewed aliases group across stores with original titles intact', () {
    final rows = [
      price('Leche Entera Lala Fresca Cartón 1L', 'chedraui'),
      price('Leche Fresca Lala Entera 1 Lto.', 'merco', amount: 31),
    ];
    final groups = groupPriceResults(rows);
    expect(groups.length, 1);
    expect(groups.single.storeCount, 2);
    expect(groups.single.best.storeSlug, 'merco');
    expect(groups.single.prices.map((p) => p.productName),
        containsAll(rows.map((p) => p.productName)));
  });

  test('quantity, currency, unreviewed and distinct variants stay separate',
      () {
    final base = price('Leche', 'one');
    for (final other in [
      price('Leche', 'two', pack: '1.8 l'),
      price('Leche', 'two', currency: 'USD'),
      price('Leche', 'two', key: 'reviewed:lala-deslactosada-1l'),
      price('Leche', 'two', key: null),
      price('Leche', 'two', key: 'automatic:lala'),
    ]) {
      expect(groupPriceResults([base, other]).length, 2);
    }
  });
}
