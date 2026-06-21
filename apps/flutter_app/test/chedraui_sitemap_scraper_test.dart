import 'package:flutter_test/flutter_test.dart';

import '../tools/ingestion/bin/chedraui_sitemap_scraper.dart' as scraper;

void main() {
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
