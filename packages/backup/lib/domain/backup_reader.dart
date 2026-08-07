import 'dart:convert';

import 'backup_file.dart';
import 'backup_format.dart';
import 'backup_header.dart';
import 'backup_reader_error.dart';

const String _eventLinePrefix = '{"kind":"event","data":';
const Set<String> _knownDataKinds = {'account', 'envelope', 'cascade', 'rate'};

/// Parses a Backup File written by [BackupWriter] back into a [BackupFile].
///
/// Event lines are unwrapped by stripping the known `{"kind":"event","data":`
/// prefix and trailing `}` rather than decoding the `data` value — that is
/// what keeps the returned payload byte-identical to what [BackupWriter]
/// pasted in (ADR-0021 §2).
///
/// All-or-nothing (ADR-0021 §6): every line is parsed before [parse]
/// returns anything, and the first line it cannot understand throws a typed
/// [BackupReaderError] naming the line number and reason — nothing is
/// returned, so a caller never sees a partially-parsed file.
class BackupReader {
  const BackupReader();

  BackupFile parse(String ndjson) {
    final rawLines = ndjson.split('\n');

    final headerEntry = _firstNonBlank(rawLines);
    if (headerEntry == null) {
      throw const InvalidHeader('el archivo está vacío');
    }

    final Map<String, dynamic> headerJson;
    try {
      headerJson = jsonDecode(headerEntry.line) as Map<String, dynamic>;
    } catch (_) {
      throw const InvalidHeader('el primer renglón no es JSON válido');
    }

    if (headerJson['kind'] != 'header') {
      throw const InvalidHeader('el primer renglón debe ser el encabezado');
    }

    final BackupHeader header;
    try {
      header = BackupHeader.fromJson(headerJson);
    } catch (_) {
      throw const InvalidHeader('faltan campos del encabezado');
    }

    if (header.format != backupFormatVersion) {
      throw UnknownFormatVersion(header.format);
    }

    final accounts = <Map<String, dynamic>>[];
    final envelopes = <Map<String, dynamic>>[];
    final cascades = <Map<String, dynamic>>[];
    final events = <String>[];
    final eventLineNumbers = <int>[];
    final rates = <Map<String, dynamic>>[];

    for (var i = headerEntry.lineNumber; i < rawLines.length; i++) {
      final lineNumber = i + 1;
      final line = rawLines[i].trim();
      if (line.isEmpty) continue;

      if (line.startsWith(_eventLinePrefix)) {
        events.add(_rawEventPayload(line, lineNumber));
        eventLineNumbers.add(lineNumber);
        continue;
      }

      final Map<String, dynamic> json;
      try {
        json = jsonDecode(line) as Map<String, dynamic>;
      } catch (_) {
        throw InvalidLine(lineNumber: lineNumber, reason: 'está incompleto');
      }

      final kind = json['kind'];
      if (!_knownDataKinds.contains(kind)) {
        throw InvalidLine(
          lineNumber: lineNumber,
          reason: 'tiene un tipo desconocido ("$kind")',
        );
      }

      final data = json['data'];
      if (data is! Map<String, dynamic>) {
        throw InvalidLine(
          lineNumber: lineNumber,
          reason: 'no tiene los datos esperados',
        );
      }

      switch (kind) {
        case 'account':
          accounts.add(data);
        case 'envelope':
          envelopes.add(data);
        case 'cascade':
          cascades.add(data);
        case 'rate':
          rates.add(data);
      }
    }

    final actualCounts =
        'event: ${events.length}, account: ${accounts.length}, '
        'envelope: ${envelopes.length}, cascade: ${cascades.length}, '
        'rate: ${rates.length}';
    if (events.length != header.counts.event ||
        accounts.length != header.counts.account ||
        envelopes.length != header.counts.envelope ||
        cascades.length != header.counts.cascade ||
        rates.length != header.counts.rate) {
      throw TruncatedFile(
        expected: header.counts.toString(),
        actual: actualCounts,
      );
    }

    return BackupFile(
      header: header,
      accounts: accounts,
      envelopes: envelopes,
      cascades: cascades,
      events: events,
      eventLineNumbers: eventLineNumbers,
      rates: rates,
    );
  }

  static ({int lineNumber, String line})? _firstNonBlank(
    List<String> rawLines,
  ) {
    for (var i = 0; i < rawLines.length; i++) {
      final trimmed = rawLines[i].trim();
      if (trimmed.isNotEmpty) return (lineNumber: i + 1, line: trimmed);
    }
    return null;
  }

  static String _rawEventPayload(String line, int lineNumber) {
    if (!line.endsWith('}')) {
      throw InvalidLine(lineNumber: lineNumber, reason: 'está incompleto');
    }
    return line.substring(_eventLinePrefix.length, line.length - 1);
  }
}
