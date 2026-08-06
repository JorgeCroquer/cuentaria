import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:rates/run_rates.dart';
import 'package:rates/sources/criptoya_source.dart';
import 'package:rates/sources/dolarapi_source.dart';

/// Publishes the exchange-rate feed for S1 (ADR-0020): reads the
/// already-published NDJSON feed from [args] first path (if any), fetches
/// DolarApi and CriptoYa independently, and writes the merged feed to
/// stdout — only when there is something new to publish.
Future<void> main(List<String> args) async {
  final existingFile = args.isNotEmpty ? File(args[0]) : null;
  final existingNdjson =
      existingFile != null && existingFile.existsSync()
          ? existingFile.readAsStringSync()
          : '';

  final client = http.Client();
  try {
    final result = await runRates(
      existingNdjson: existingNdjson,
      sources: [DolarApiSource(client), CriptoYaSource(client)],
    );
    if (result != null) stdout.write(result);
  } finally {
    client.close();
  }
}
