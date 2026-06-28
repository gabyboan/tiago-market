import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../tools/ingestion/bin/home_depot_mx_scraper.dart' as scraper;

void main() {
  group('Home Depot branch-local scraping', () {
    test('parses store locator branches with geolocation', () {
      final branches = scraper.parseStoreLocatorBranches(
        jsonEncode({
          'PhysicalStore': [
            {
              'Description': [
                {'displayStoreName': 'Centro'},
              ],
              'city': 'Del. Venustiano Carranza',
              'postalCode': '15980                                   ',
              'latitude': '19.41476',
              'longitude': '-99.11683',
              'addressLine': ['Av. Del Taller #370', 'Col. 24 de Abril'],
              'stateOrProvinceName': 'Ciudad de Mexico',
              'storeName': '8860',
              'uniqueID': '12592',
              'Attribute': [
                {'name': 'MarketId', 'value': '21'},
              ],
            },
          ],
        }),
      );

      expect(branches, hasLength(1));
      expect(branches.single.externalKey, 'home-depot-mx:8860');
      expect(branches.single.name, 'The Home Depot Centro');
      expect(branches.single.uniqueId, '12592');
      expect(branches.single.latitude, 19.41476);
      expect(branches.single.longitude, -99.11683);
    });

    test('extracts branch price and inventory from search components', () {
      final branch = testBranch();
      final products = scraper.parseSearchProducts(
        jsonEncode({
          'contents': [
            {
              'name': 'KIT PARA PINTAR BEREL',
              'seo': {'href': '/g/kit-para-pintar-berel'},
              'components': [
                {
                  'partNumber': '111338',
                  'uniqueID': '56812',
                  'manufacturer': 'BERELINTE',
                  'x_prices.8860.mxn': '2539.0',
                  'inventories.12592.quantity': '12.0',
                  'price': [
                    {'usage': 'Offer', 'currency': 'MXN', 'value': '2539.0'},
                  ],
                },
              ],
            },
          ],
        }),
        branch: branch,
        sourceUrl:
            'https://www.homedepot.com.mx/search/resources/api/v2/products?physicalStoreId=8860',
      );

      expect(products, hasLength(1));
      expect(products.single.partNumber, '111338');
      expect(products.single.price, 2539.0);
      expect(products.single.inventoryQuantity, 12.0);
      expect(products.single.available, isTrue);
      expect(
        products.single.productUrl,
        'https://www.homedepot.com.mx/g/kit-para-pintar-berel',
      );
    });

    test('builds geolocated staging record from detail evidence', () {
      final branch = testBranch();
      final detail = scraper.parseProductDetail(
        jsonEncode({
          'contents': [
            {
              'partNumber': '111338',
              'uniqueID': '56812',
              'name':
                  'Pintura Berel Berelinte Vinil Acrilica Interior/Exterior 19L Color Ostion Mate',
              'manufacturer': 'BERELINTE',
              'x_prices.8860.mxn': '2539.0',
              'inventories.12592.quantity': '12.0',
              'seo': {
                'href':
                    '/p/berelinte-pintura-berel-berelinte-vinil-acrilica-interior-exterior-19l-color-ostion-mate-berelinte-111338',
              },
              'thumbnail': '/hclstore/HDM-CAS/productos/111338/111338.jpg',
              'price': [
                {'usage': 'Offer', 'currency': 'MXN', 'value': '2539.0'},
              ],
            },
          ],
        }),
        branch: branch,
        sourceUrl:
            'https://www.homedepot.com.mx/search/resources/api/v2/products?partNumber=111338&physicalStoreId=8860',
      );

      final record = scraper.buildStageRecord(
        branch: branch,
        product: detail!,
        searchTerm: 'pintura',
      );

      expect(record, isNotNull);
      expect(record!['source'], 'home-depot-mx');
      expect(
        record['source_product_name'],
        contains('Pintura Berel Berelinte'),
      );
      expect(
        record['normalized_name'],
        contains('pintura berel berelinte vinil acrilica'),
      );
      expect(record['presentation'], '19 l');
      expect(record['price'], 2539.0);
      expect(record['branch_external_key'], 'home-depot-mx:8860');
      expect(record['branch_name'], 'The Home Depot Centro');
      expect(record['latitude'], 19.41476);
      expect(record['longitude'], -99.11683);
      expect(record['store_product_url'], startsWith('https://'));
      expect(
        record['image_url'],
        'https://cdn.homedepot.com.mx/hclstore/HDM-CAS/productos/111338/111338.jpg',
      );
      expect(record['content_hash'], matches(RegExp(r'^[0-9a-f]{16}$')));
    });

    test('rejects a generic offer without branch-specific price evidence', () {
      final result = scraper.parseProductEvidenceFromJson(
        {
          'partNumber': '111338',
          'name': 'Pintura generica',
          'inventories.12592.quantity': '12',
          'seo': {'href': '/p/pintura-generica-111338'},
          'price': [
            {'usage': 'Offer', 'currency': 'MXN', 'value': '999'},
          ],
        },
        branch: testBranch(),
        sourceUrl:
            'https://www.homedepot.com.mx/search/resources/api/v2/products?physicalStoreId=8860',
      );

      expect(result.evidence, isNull);
      expect(result.rejectionReason, 'missing_branch_price_field');
    });

    test('ships the controlled commercial demo terms', () {
      final options = scraper.ScraperOptions.parse(const []);

      expect(options.branchLimit, 3);
      expect(options.productsPerTerm, 5);
      expect(options.terms, scraper.defaultDemoTerms);
    });

    test('attributes the historical 13 to 1 gap to the global limit', () {
      final summary = scraper.BranchScrapeSummary(branch: testBranch());
      final term = summary.forTerm('pintura')
        ..found = 13
        ..qualified = 13
        ..probed = 1
        ..emitted = 1;
      term.reject('global_limit', 12);

      final report = summary.toHumanReadable();

      expect(
        report,
        contains('found=13, qualified=13, probed=1, emitted=1, rejected=12'),
      );
      expect(report, contains('categories=[limite=12]'));
      expect(report, contains('reasons=[global_limit=12]'));
    });

    test('groups strict rejection reasons without relaxing evidence', () {
      expect(
        scraper.rejectionCategory('missing_branch_price_field'),
        'precio_ausente',
      );
      expect(
        scraper.rejectionCategory('missing_branch_inventory_field'),
        'stock_invalido',
      );
      expect(
        scraper.rejectionCategory('duplicate_product_across_terms'),
        'sku_duplicado',
      );
      expect(scraper.rejectionCategory('out_of_stock'), 'filtro_deliberado');
      expect(
        scraper.rejectionCategory('missing_official_product_url'),
        'evidencia_incompleta',
      );
    });
  });
}

scraper.HomeDepotBranch testBranch() => scraper.HomeDepotBranch(
  storeNumber: '8860',
  uniqueId: '12592',
  externalKey: 'home-depot-mx:8860',
  name: 'The Home Depot Centro',
  address: 'Av. Del Taller #370, Col. 24 de Abril',
  municipality: 'Del. Venustiano Carranza',
  state: 'Ciudad de Mexico',
  postalCode: '15980',
  latitude: 19.41476,
  longitude: -99.11683,
  marketId: '21',
);
