import 'package:flutter_test/flutter_test.dart';

import '../tools/ingestion/bin/steren_sitemap_scraper.dart' as scraper;

void main() {
  group('parseSterenProductPage', () {
    test('extracts product evidence from JSON-LD offer data', () {
      final record = scraper.parseSterenProductPage(
        productUrl:
            'https://www.steren.com.mx/placa-fenolica-perforada-de-4-5-cm-x-4-5-cm.html',
        html: '''
<html>
<head>
  <meta property="product:price:amount" content="12.000001"/>
  <meta property="product:availability" content="in stock"/>
  <script type="application/ld+json">
    {
      "@context": "http://schema.org",
      "@type": "Product",
      "name": "Placa fenolica perforada de 4,5 cm x 4,5 cm",
      "sku": "155",
      "image": "https://www.steren.com.mx/media/catalog/product/image.jpg",
      "category": "Impresion de circuitos y accesorios",
      "model": "155",
      "offers": {
        "@type": "Offer",
        "url": "https://www.steren.com.mx/placa-fenolica-perforada-de-4-5-cm-x-4-5-cm.html",
        "price": "12.00",
        "priceCurrency": "MXN",
        "priceValidUntil": "2030-01-01",
        "availability": "http://schema.org/InStock",
        "sku": "155"
      }
    }
  </script>
</head>
</html>
''',
      );

      expect(record, isNotNull);
      expect(record!['source'], 'steren-mx');
      expect(
        record['source_product_name'],
        'Placa fenolica perforada de 4,5 cm x 4,5 cm',
      );
      expect(record['normalized_name'],
          'placa fenolica perforada de 4 5 cm x 4 5 cm');
      expect(record['price'], 12.0);
      expect(record['currency'], 'MXN');
      expect(record['available'], isTrue);
      expect(record['external_reference'], '155');
      expect(record['presentation'], '1 pieza');
      expect(record['content_hash'], matches(RegExp(r'^[0-9a-f]{16}$')));
    });

    test('falls back to product meta price when offer price is missing', () {
      final record = scraper.parseSterenProductPage(
        productUrl: 'https://www.steren.com.mx/producto.html',
        html: '''
<html>
<head>
  <meta property="product:price:amount" content="99.50"/>
  <meta property="product:price:currency" content="MXN"/>
  <script type="application/ld+json">
    {
      "@context": "http://schema.org",
      "@type": "Product",
      "name": "Cable HDMI",
      "sku": "299",
      "offers": {
        "@type": "Offer",
        "url": "https://www.steren.com.mx/producto.html",
        "availability": "http://schema.org/OutOfStock",
        "sku": "299"
      }
    }
  </script>
</head>
</html>
''',
      );

      expect(record, isNotNull);
      expect(record!['price'], 99.5);
      expect(record['available'], isFalse);
    });
  });
}
