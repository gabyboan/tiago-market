import 'dart:async';
import 'dart:io';

const sourceScripts = <String, String>{
  'home-depot-mx': 'tools/ingestion/bin/home_depot_mx_scraper.dart',
  'chedraui-mx': 'tools/ingestion/bin/chedraui_sitemap_scraper.dart',
  'steren-mx': 'tools/ingestion/bin/steren_sitemap_scraper.dart',
  'merco-mx': 'tools/ingestion/python/merco_online_scraper.py',
};

Future<void> main(List<String> args) async {
  final options = RunnerOptions.parse(args);
  if (options.showHelp) {
    stdout.write(RunnerOptions.helpText);
    return;
  }

  final unknownSources = options.sources
      .where((source) => !sourceScripts.containsKey(source))
      .toList(growable: false);
  if (unknownSources.isNotEmpty) {
    stderr.writeln(
      'Unknown source(s): ${unknownSources.join(', ')}. '
      'Available: ${sourceScripts.keys.join(', ')}',
    );
    exitCode = 64;
    return;
  }

  await Directory(options.outputDirectory).create(recursive: true);
  final runId = _timestamp(DateTime.now().toUtc());
  var failed = false;

  for (final source in options.sources) {
    final outputPath =
        '${options.outputDirectory}${Platform.pathSeparator}$source-$runId.ndjson';
    final command = _commandFor(
      source: source,
      outputPath: outputPath,
      options: options,
    );

    stdout.writeln('Running $source -> $outputPath');
    final result = await Process.run(
      command.first,
      command.skip(1).toList(growable: false),
      runInShell: false,
    );
    stdout.write(result.stdout);
    stderr.write(result.stderr);

    if (result.exitCode != 0) {
      failed = true;
      stderr.writeln('$source failed with exit code ${result.exitCode}.');
      if (!options.continueOnError) {
        break;
      }
    } else {
      stdout.writeln('$source completed.');
    }
  }

  if (failed) {
    exitCode = 1;
  }
}

List<String> _commandFor({
  required String source,
  required String outputPath,
  required RunnerOptions options,
}) {
  final script = sourceScripts[source]!;
  final command = <String>[
    if (script.endsWith('.py')) 'python3' else Platform.resolvedExecutable,
    if (!script.endsWith('.py')) 'run',
    script,
    '--out',
    outputPath,
    '--limit',
    '${options.limit}',
    '--delay-ms',
    '${options.delayMs}',
  ];

  if (source == 'home-depot-mx') {
    command.addAll([
      '--latitude',
      '${options.latitude}',
      '--longitude',
      '${options.longitude}',
      '--branch-limit',
      '${options.branchLimit}',
      '--terms',
      options.terms.join(','),
    ]);
  }

  return command;
}

String _timestamp(DateTime value) => value.toIso8601String()
    .replaceAll(RegExp(r'[^0-9]'), '')
    .substring(0, 15);

class RunnerOptions {
  RunnerOptions({
    required this.sources,
    required this.outputDirectory,
    required this.limit,
    required this.delayMs,
    required this.branchLimit,
    required this.latitude,
    required this.longitude,
    required this.terms,
    required this.continueOnError,
    required this.showHelp,
  });

  final List<String> sources;
  final String outputDirectory;
  final int limit;
  final int delayMs;
  final int branchLimit;
  final double latitude;
  final double longitude;
  final List<String> terms;
  final bool continueOnError;
  final bool showHelp;

  factory RunnerOptions.parse(List<String> args) {
    var sources = sourceScripts.keys.toList(growable: false);
    var outputDirectory = '/tmp/tiago-market-ingestion';
    var limit = 10;
    var delayMs = 1500;
    var branchLimit = 3;
    var latitude = 19.432608;
    var longitude = -99.133209;
    var terms = const [
      'leche',
      'huevo',
      'arroz',
      'aceite',
      'frijol',
    ];
    var continueOnError = false;
    var showHelp = false;

    String valueAt(int index, String option) {
      if (index + 1 >= args.length) {
        throw FormatException('$option requires a value');
      }
      return args[index + 1];
    }

    for (var index = 0; index < args.length; index++) {
      switch (args[index]) {
        case '--help':
        case '-h':
          showHelp = true;
        case '--sources':
          sources = valueAt(index, '--sources')
              .split(',')
              .map((source) => source.trim())
              .where((source) => source.isNotEmpty)
              .toList(growable: false);
          index++;
        case '--output-dir':
          outputDirectory = valueAt(index, '--output-dir');
          index++;
        case '--limit':
          limit = int.parse(valueAt(index, '--limit'));
          index++;
        case '--delay-ms':
          delayMs = int.parse(valueAt(index, '--delay-ms'));
          index++;
        case '--branch-limit':
          branchLimit = int.parse(valueAt(index, '--branch-limit'));
          index++;
        case '--latitude':
          latitude = double.parse(valueAt(index, '--latitude'));
          index++;
        case '--longitude':
          longitude = double.parse(valueAt(index, '--longitude'));
          index++;
        case '--terms':
          terms = valueAt(index, '--terms')
              .split(',')
              .map((term) => term.trim())
              .where((term) => term.isNotEmpty)
              .toList(growable: false);
          index++;
        case '--continue-on-error':
          continueOnError = true;
        default:
          throw FormatException('Unknown option: ${args[index]}');
      }
    }

    if (sources.isEmpty) {
      throw FormatException('--sources cannot be empty');
    }
    if (limit <= 0 || delayMs < 0 || branchLimit <= 0 || terms.isEmpty) {
      throw FormatException('limits and terms must be positive');
    }

    return RunnerOptions(
      sources: sources,
      outputDirectory: outputDirectory,
      limit: limit,
      delayMs: delayMs,
      branchLimit: branchLimit,
      latitude: latitude,
      longitude: longitude,
      terms: terms,
      continueOnError: continueOnError,
      showHelp: showHelp,
    );
  }

  static const helpText = '''Usage:
  dart run tools/ingestion/bin/multi_source_ingestion.dart [options]

Options:
  --sources <list>       Comma-separated sources. Default: all available.
  --output-dir <path>    Directory for one NDJSON file per source.
  --limit <number>       Maximum records per sitemap source.
  --delay-ms <number>    Delay between requests for each scraper.
  --branch-limit <n>     Home Depot branches near the selected coordinates.
  --latitude <number>    Search latitude for Home Depot.
  --longitude <number>   Search longitude for Home Depot.
  --terms <list>         Comma-separated product terms for Home Depot.
  --continue-on-error    Run remaining sources after a failure.
  -h, --help             Show this help.

Available sources:
  home-depot-mx, chedraui-mx, steren-mx, merco-mx

Merco requires python3, captures at most 20 reviewed URLs, and enforces a
minimum 5-second interval. Its default sample contains six product URLs.

The runner only creates NDJSON. Validate and publish each file separately with
stage_ndjson.dart; it never writes to Supabase directly.
''';
}
