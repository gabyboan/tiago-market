import 'package:flutter_test/flutter_test.dart';

import '../tools/ingestion/bin/stage_ndjson.dart' as stage;

void main() {
  group('validateRecords', () {
    test('requires content hash for real staging rows', () {
      final record = validRecord()..remove('content_hash');

      expect(
        stage.validateRecords([record]),
        contains('Line 1 missing string field: content_hash'),
      );
    });

    test('requires branch evidence and Mexico coordinates', () {
      final record = validRecord()
        ..remove('branch_external_key')
        ..['latitude'] = null
        ..['longitude'] = -120;

      expect(
        stage.validateRecords([record]),
        containsAll([
          'Line 1 missing string field: branch_external_key',
          'Line 1 has invalid Mexico latitude: null',
          'Line 1 has invalid Mexico longitude: -120',
        ]),
      );
    });
  });

  group('buildStageSql', () {
    test('skips records already staged with same source and content hash', () {
      final sql = stage.buildStageSql([
        validRecord(),
      ], runSource: 'chedraui-mx');

      expect(sql, contains('where not exists'));
      expect(sql, contains('on conflict (source, content_hash)'));
      expect(sql, contains('reused_staging'));
      expect(sql, contains('skipped_existing_snapshots'));
    });

    test('does not bind a shared store product to one branch', () {
      final sql = stage.buildStageSql([
        validRecord(),
      ], runSource: 'home-depot-mx');

      expect(sql, contains('store_product_input as'));
      expect(sql, contains('branch_id = null'));
      expect(
        sql,
        contains('distinct on (store_product_id, branch_id, captured_at)'),
      );
    });
  });

  group('preflight', () {
    test('deduplicates source and content hash without rewriting text', () {
      final record = validRecord();
      final report = stage.buildPreflightReport(
        stage.NdjsonInput(
          records: [
            stage.InputRecord(lineNumber: 1, value: record),
            stage.InputRecord(
              lineNumber: 2,
              value: Map<String, dynamic>.from(record),
            ),
          ],
          parseErrors: const [],
          inputRecords: 2,
        ),
      );

      expect(report.accepted, 2);
      expect(report.rejected, 0);
      expect(report.publishable, 1);
      expect(report.duplicateInputRecords, 1);
      expect(
        report.publishableRecords.single['source_product_name'],
        'Croissant  Novia',
      );
    });

    test('rejects unknown evidence and timestamps without timezone', () {
      final record = validRecord()
        ..['evidence_kind'] = 'unknown'
        ..['captured_at'] = '2026-06-19 00:00:00';

      final codes = stage.validateRecord(record).map((issue) => issue.code);
      expect(codes, containsAll(['unknown_evidence', 'invalid_captured_at']));
    });
  });
}

Map<String, dynamic> validRecord() => {
  'source': 'chedraui-mx',
  'store_brand': 'Chedraui',
  'store_slug': 'chedraui-mx',
  'source_product_name': 'Croissant  Novia',
  'normalized_name': 'croissant novia',
  'category': 'Panaderia',
  'presentation': '1 pieza',
  'currency': 'MXN',
  'captured_at': '2026-06-19T00:00:00Z',
  'observed_at': '2026-06-19T00:00:00Z',
  'source_url': 'https://www.chedraui.com.mx/croissant-novia-3106012/p',
  'evidence_kind': 'product_page',
  'store_product_url': 'https://www.chedraui.com.mx/croissant-novia-3106012/p',
  'content_hash': '6d15b287d67fcc6d',
  'price': 26.0,
  'confidence_score': 0.9,
  'is_synthetic': false,
  'review_status': 'accepted',
  'available': true,
  'branch_external_key': 'chedraui-sucursal-123',
  'branch_name': 'Chedraui Centro',
  'branch_address': 'Av. Ejemplo 123',
  'branch_municipality': 'Cuauhtemoc',
  'branch_state': 'Ciudad de Mexico',
  'latitude': 19.4326,
  'longitude': -99.1332,
  'external_reference': '3106012',
  'image_url': null,
  'raw_payload': {'source': 'test'},
};
