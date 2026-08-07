import 'dart:convert';

import 'backup_file.dart';
import 'backup_format.dart';
import 'backup_header.dart';

const String _eventLinePrefix = '{"kind":"event","data":';

/// Parses a Backup File written by [BackupWriter] back into a [BackupFile].
///
/// Event lines are unwrapped by stripping the known `{"kind":"event","data":`
/// prefix and trailing `}` rather than decoding the `data` value — that is
/// what keeps the returned payload byte-identical to what [BackupWriter]
/// pasted in (ADR-0021 §2).
class BackupReader {
  const BackupReader();

  BackupFile parse(String ndjson) {
    final lines =
        ndjson
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();

    if (lines.isEmpty) {
      throw const FormatException('Backup file is empty.');
    }

    final headerJson = jsonDecode(lines.first) as Map<String, dynamic>;
    if (headerJson['kind'] != 'header') {
      throw const FormatException(
        'First line of a backup file must be the header.',
      );
    }

    final header = BackupHeader.fromJson(headerJson);
    if (header.format != backupFormatVersion) {
      throw FormatException(
        'Unsupported backup format ${header.format}; expected $backupFormatVersion.',
      );
    }

    final accounts = <Map<String, dynamic>>[];
    final envelopes = <Map<String, dynamic>>[];
    final cascades = <Map<String, dynamic>>[];
    final events = <String>[];
    final rates = <Map<String, dynamic>>[];

    for (final line in lines.skip(1)) {
      if (line.startsWith(_eventLinePrefix)) {
        events.add(_rawEventPayload(line));
        continue;
      }

      final json = jsonDecode(line) as Map<String, dynamic>;
      final data = json['data'] as Map<String, dynamic>;
      switch (json['kind']) {
        case 'account':
          accounts.add(data);
        case 'envelope':
          envelopes.add(data);
        case 'cascade':
          cascades.add(data);
        case 'rate':
          rates.add(data);
        default:
          throw FormatException('Unknown backup line kind: ${json['kind']}');
      }
    }

    return BackupFile(
      header: header,
      accounts: accounts,
      envelopes: envelopes,
      cascades: cascades,
      events: events,
      rates: rates,
    );
  }

  static String _rawEventPayload(String line) {
    if (!line.endsWith('}')) {
      throw FormatException('Malformed event line: $line');
    }
    return line.substring(_eventLinePrefix.length, line.length - 1);
  }
}
