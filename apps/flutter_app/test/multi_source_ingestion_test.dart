import 'package:flutter_test/flutter_test.dart';

import '../tools/ingestion/bin/multi_source_ingestion.dart';

void main() {
  test('selects the requested sources and keeps defaults safe', () {
    final options = RunnerOptions.parse([
      '--sources',
      'home-depot-mx, chedraui-mx',
      '--output-dir',
      '/tmp/ingestion-test',
      '--delay-ms',
      '7000',
    ]);

    expect(options.sources, ['home-depot-mx', 'chedraui-mx']);
    expect(options.outputDirectory, '/tmp/ingestion-test');
    expect(options.delayMs, 7000);
    expect(options.continueOnError, isFalse);
  });

  test('uses all known sources when none are selected', () {
    final options = RunnerOptions.parse(const []);

    expect(options.sources, sourceScripts.keys);
    expect(options.branchLimit, 3);
    expect(options.terms, contains('leche'));
  });

  test('rejects empty source lists', () {
    expect(
      () => RunnerOptions.parse(['--sources', '']),
      throwsFormatException,
    );
  });
}