import 'dart:convert';
import 'dart:io';

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

    test('accepts online records without assigning a branch', () {
      final record = validRecord()
        ..['price_scope'] = 'online'
        ..['branch_external_key'] = null
        ..['branch_name'] = null
        ..['branch_address'] = null
        ..['branch_municipality'] = null
        ..['branch_state'] = null
        ..['latitude'] = null
        ..['longitude'] = null;

      expect(stage.validateRecords([record]), isEmpty);
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

    test('publishes online records with an explicit online scope', () {
      final record = validRecord()
        ..['price_scope'] = 'online'
        ..['branch_external_key'] = null
        ..['branch_name'] = null
        ..['branch_address'] = null
        ..['branch_municipality'] = null
        ..['branch_state'] = null
        ..['latitude'] = null
        ..['longitude'] = null;

      final sql = stage.buildStageSql([record], runSource: 'chedraui-mx');

      expect(sql, contains("'price_scope', coalesce"));
      expect(sql, contains("normalized_payload->>'price_scope' = 'online'"));
      expect(sql, contains('c.price_scope'));
      expect(sql, contains('on conflict do nothing'));
    });
  });

  group('preflight', () {
    test('serializes validation, parsing, dedupe and unchanged payloads', () {
      final record = validRecord();
      final invalidRecord = validRecord()..['price'] = 0;
      final report = stage.buildPreflightReport(
        stage.NdjsonInput(
          records: [
            stage.InputRecord(lineNumber: 1, value: record),
            stage.InputRecord(
              lineNumber: 2,
              value: Map<String, dynamic>.from(record),
            ),
            stage.InputRecord(lineNumber: 4, value: invalidRecord),
          ],
          parseErrors: const ['Line 3 is not a JSON object.'],
          inputRecords: 4,
        ),
      );

      final json = jsonDecode(jsonEncode(report.toJson()));
      expect(json, {
        'input_records': 4,
        'accepted': 2,
        'rejected': 2,
        'duplicate_input_records': 1,
        'publishable': 1,
        'rejected_records': [
          {
            'line': 3,
            'source': '<unparsed>',
            'branch': '<unparsed>',
            'category': '<unparsed>',
            'reasons': [
              {
                'code': 'not_json_object',
                'message': 'Line 3 is not a JSON object.',
              },
            ],
          },
          {
            'line': 4,
            'source': record['source'],
            'branch': record['branch_external_key'],
            'category': record['category'],
            'reasons': [
              {'code': 'invalid_price', 'message': 'has invalid price: 0'},
            ],
          },
        ],
        'publishable_records': [record],
      });
    });

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

  group('JSON report option', () {
    test('coexists with existing report, SQL and partial flags', () {
      final options = stage.StageOptions.parse([
        '--input',
        'input.ndjson',
        '--json-report',
        'report.json',
        '--report-out',
        'report.txt',
        '--sql-out',
        'stage.sql',
        '--allow-partial',
      ]);

      expect(options.jsonReportPath, 'report.json');
      expect(options.reportOutPath, 'report.txt');
      expect(options.sqlOutPath, 'stage.sql');
      expect(options.allowPartial, isTrue);
      expect(options.execute, isFalse);
      expect(options.validateOnly, isFalse);
      expect(
          stage.StageOptions.parse(['--input', 'input.ndjson']).jsonReportPath,
          isNull);
      expect(
        () => stage.StageOptions.parse(
            ['--input', 'input.ndjson', '--json-report']),
        throwsArgumentError,
      );
    });

    test('writes JSON before validate-only returns for rejected input',
        () async {
      final directory = await Directory.systemTemp.createTemp('stage_report_');
      final originalExitCode = exitCode;
      addTearDown(() async {
        exitCode = originalExitCode;
        await directory.delete(recursive: true);
      });
      final input = File('${directory.path}/input.ndjson');
      final output = File('${directory.path}/report.json');
      final sql = File('${directory.path}/stage.sql');
      final record = validRecord();
      await input.writeAsString('${jsonEncode(record)}\ninvalid json\n');

      await stage.main([
        '--input',
        input.path,
        '--json-report',
        output.path,
        '--sql-out',
        sql.path,
        '--validate-only',
      ]);

      final json = jsonDecode(await output.readAsString());
      expect(exitCode, 2);
      expect(json['input_records'], 2);
      expect(json['accepted'], 1);
      expect(json['rejected'], 1);
      expect(json['publishable_records'], [record]);
      expect(json['rejected_records'].single['line'], 2);
      expect(json['rejected_records'].single['reasons'].single['code'],
          'invalid_json');
      expect(await sql.exists(), isFalse);
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
      'captured_at': DateTime.now().toUtc().toIso8601String(),
      'observed_at': DateTime.now().toUtc().toIso8601String(),
      'source_url': 'https://www.chedraui.com.mx/croissant-novia-3106012/p',
      'evidence_kind': 'product_page',
      'store_product_url':
          'https://www.chedraui.com.mx/croissant-novia-3106012/p',
      'content_hash': '6d15b287d67fcc6d',
      'price': 26.0,
      'confidence_score': 0.9,
      'is_synthetic': false,
      'review_status': 'accepted',
      'available': true,
      'branch_external_key':
          'chedraui-sucursal-123', // gitleaks:allow -- fixture branch ID, not a credential
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
