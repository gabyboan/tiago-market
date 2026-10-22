import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

import '../tools/ingestion/bin/chedraui_sitemap_scraper.dart' as scraper;

const url = 'https://www.chedraui.com.mx/fixture-leche-3012008/p';

Map<String, dynamic> runtime() => {
      'account': 'chedrauimx',
      'culture': {'currency': 'MXN'},
      'route': {
        'id': 'store.product',
        'canonicalPath': '/fixture-leche-3012008/p',
        'params': {'id': '3012008'},
      },
    };

Map<String, dynamic> ref(String id) => {'type': 'id', 'id': id};

Map<String, dynamic> state() => {
      'Product:fixture-leche-3012008': {
        'productId': '3012008',
        'productName': 'Fixture leche 1L',
        'linkText': 'fixture-leche-3012008',
        'items': [ref('sku')],
      },
      'sku': {
        'itemId': '3012008',
        'measurementUnit': 'un',
        'unitMultiplier': 1,
        'sellers': [ref('seller')],
      },
      'seller': {
        'sellerId': '1',
        'sellerName': 'Chedraui',
        'commertialOffer': ref('offer'),
      },
      'offer': {
        'Price': 34,
        'ListPrice': 34,
        'AvailableQuantity': 100,
        'PriceValidUntil': '2027-01-01T00:00:00Z',
        'priceToken': 'private-fixture-checkout-token',
      },
      'recommendation': {'Price': 999, 'productName': 'Other product'},
    };

Map<String, Object?>? parse(Map<String, dynamic> data,
        {Map<String, dynamic>? context}) =>
    scraper.parseChedrauiProductPage(
      productUrl: url,
      observedAt: DateTime.utc(2026, 10, 21),
      html:
          '<template data-type="json" data-varname="__RUNTIME__"><script>${jsonEncode(context ?? runtime())}</script></template>'
          '<template data-type="json" data-varname="__STATE__"><script>${jsonEncode(data)}</script></template>',
    );

void main() {
  test('reads the bound first-party offer from current VTEX templates', () {
    final row = parse(state())!;
    expect(row['price'], 34);
    expect(row['available'], true);
    expect(row['presentation'], '1 l');
    expect(row['store_product_url'], url);
    expect(row['captured_at'], '2026-10-21T00:00:00.000Z');
    expect((row['raw_payload'] as Map)['price_evidence'],
        'sku_bound_vtex_state_offer');
    expect(jsonEncode(row), isNot(contains('private-fixture-checkout-token')));
    expect(jsonEncode(row), isNot(contains('json_ld_product')));
  });

  test('rejects a different currency, route or SKU', () {
    expect(
        parse(state(), context: runtime()..['culture'] = {'currency': 'USD'}),
        isNull);
    final context = runtime();
    context['route']['params']['id'] = '9999999';
    expect(parse(state(), context: context), isNull);
    final data = state();
    data['sku']['itemId'] = '9999999';
    expect(parse(data), isNull);
  });

  test('rejects ambiguous variants, weighted units and changed sellers', () {
    final variants = state();
    variants['Product:fixture-leche-3012008']['items'].add(ref('sku'));
    expect(parse(variants), isNull);
    for (final changes in [
      {'measurementUnit': 'kg'},
      {'unitMultiplier': 2},
    ]) {
      final data = state();
      (data['sku'] as Map).addAll(changes);
      expect(parse(data), isNull);
    }
    final data = state();
    data['seller']['sellerId'] = 'marketplace';
    expect(parse(data), isNull);
  });

  test(
      'rejects discounts and expired offers; preserves explicit unavailability',
      () {
    final discounted = state();
    discounted['offer']['ListPrice'] = 40;
    expect(parse(discounted), isNull);
    final expired = state();
    expired['offer']['PriceValidUntil'] = '2020-01-01T00:00:00Z';
    expect(parse(expired), isNull);
    final unavailable = state();
    unavailable['offer']['AvailableQuantity'] = 0;
    expect(parse(unavailable)!['available'], false);
  });
}
