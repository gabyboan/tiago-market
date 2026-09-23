import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

import '../tools/ingestion/bin/chedraui_sitemap_scraper.dart' as scraper;

void main() {
  group('SKU-bound official offers', () {
    const url = 'https://www.chedraui.com.mx/fixture-leche-3012008/p';
    final observed = DateTime.utc(2026, 9, 23, 15);
    Map<String, dynamic> product() => {
          '@type': 'Product',
          '@id': url,
          'mpn': '3012008',
          'sku': '03012008',
          'name': 'Fixture leche 1L',
          'offers': {
            '@type': 'AggregateOffer',
            'offers': [
              <String, dynamic>{
                '@type': 'Offer',
                'sku': '03012008',
                'price': 34,
                'priceCurrency': 'MXN',
                'availability': 'http://schema.org/InStock',
                'priceValidUntil': '2027-01-01T00:00:00Z',
                'seller': {'name': 'Chedraui'}
              },
            ]
          },
        };
    Map<String, Object?>? parse(Map<String, dynamic> node,
            {String prefix = '', DateTime? time}) =>
        scraper.parseChedrauiProductPage(
          productUrl: url,
          html:
              '$prefix<script type="application/ld+json">${jsonEncode(node)}</script>',
          observedAt: time ?? observed,
        );

    test('ignores unrelated prices and preserves observation and offer', () {
      final row = parse(product(), prefix: '"Price":1,"AvailableQuantity":0')!;
      expect(row['price'], 34);
      expect(row['available'], true);
      expect(row['observed_at'], observed.toIso8601String());
      expect(row['branch_external_key'], isNull);
      expect((row['raw_payload'] as Map)['json_ld_product'], product());
    });

    test('rejects identity, currency, seller and availability mismatches', () {
      for (final change in [
        {'sku': 'other'},
        {'priceCurrency': 'USD'},
        {'price': 'NaN'},
        {'price': 0},
        {'availability': null},
        {
          'seller': {'name': 'Other seller'}
        },
        {'priceValidUntil': '2026-06-01T00:00:00Z'},
      ]) {
        final node = product();
        (node['offers']['offers'][0] as Map).addAll(change);
        expect(parse(node), isNull, reason: '$change');
      }
      expect(parse(product()..['mpn'] = 'other'), isNull);
      expect(parse(product()..['@id'] = '$url-other'), isNull);
      expect(
          scraper.parseChedrauiProductPage(
              productUrl: url, html: '"productName":"Leche 1L","Price":34'),
          isNull);
    });

    test('rejects multiple offers and ambiguous quantity', () {
      final node = product();
      (node['offers']['offers'] as List).add(node['offers']['offers'][0]);
      expect(parse(node), isNull);
      expect(parse(product()..['name'] = 'Leche'), isNull);
      expect(parse(product()..['name'] = 'Leche 6 piezas de 1L'), isNull);
    });

    test('same receipt deduplicates but fresh unchanged price can refresh', () {
      expect(
          parse(product())!['content_hash'], parse(product())!['content_hash']);
      expect(
          parse(product())!['content_hash'],
          isNot(parse(product(),
              time: observed.add(const Duration(hours: 1)))!['content_hash']));
    });
  });
  group('inferPresentation', () {
    test('keeps explicit numeric presentations', () {
      expect(scraper.inferPresentation('Aceite vegetal 850 ml'), '850 ml');
      expect(scraper.inferPresentation('Refresco cola 2 lt'), '2 l');
      expect(scraper.inferPresentation('Pan dulce 3 piezas'), '3 piezas');
    });

    test('infers unit-only weighted products', () {
      expect(
        scraper.inferPresentation('Chambarete sin Hueso Res Kosher kg'),
        '1 kg',
      );
    });

    test('falls back to one piece', () {
      expect(scraper.inferPresentation('Croissant Novia'), '1 pieza');
    });
  });

  group('stableHash', () {
    test('returns unsigned fixed-width hexadecimal text', () {
      final hash = scraper.stableHash(
        'chedraui-mx|https://www.chedraui.com.mx/chambarete-sin-hueso-res-kosher-kg-3102636/p|329.0|true',
      );

      expect(hash, matches(RegExp(r'^[0-9a-f]{16}$')));
    });
  });
}
