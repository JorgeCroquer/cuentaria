import 'dart:convert';

import 'backup_format.dart';
import 'backup_header.dart';

/// Serializes a Backup File to NDJSON (ADR-0021 §1-2): one line per object,
/// header first, then account/envelope/cascade/event/rate lines in that
/// order.
///
/// Event lines are the one exception to "every line is `jsonEncode`d": each
/// [events] entry is already the canonical, single-line JSON `EventCodec`
/// wrote to `events.payload`, so it is pasted into its envelope by string
/// concatenation rather than decoded and re-encoded — the only way to
/// guarantee the backed-up event is byte-identical to the stored one.
class BackupWriter {
  const BackupWriter();

  String write({
    required DateTime exportedAt,
    List<Map<String, dynamic>> accounts = const [],
    List<Map<String, dynamic>> envelopes = const [],
    List<Map<String, dynamic>> cascades = const [],
    List<String> events = const [],
    List<Map<String, dynamic>> rates = const [],
  }) {
    final header = BackupHeader(
      format: backupFormatVersion,
      app: backupAppName,
      exportedAt: exportedAt,
      counts: BackupCounts(
        event: events.length,
        account: accounts.length,
        envelope: envelopes.length,
        cascade: cascades.length,
        rate: rates.length,
      ),
    );

    final lines = <String>[jsonEncode(header.toJson())];
    for (final account in accounts) {
      lines.add(jsonEncode({'kind': 'account', 'data': account}));
    }
    for (final envelope in envelopes) {
      lines.add(jsonEncode({'kind': 'envelope', 'data': envelope}));
    }
    for (final cascade in cascades) {
      lines.add(jsonEncode({'kind': 'cascade', 'data': cascade}));
    }
    for (final payload in events) {
      lines.add('{"kind":"event","data":$payload}');
    }
    for (final rate in rates) {
      lines.add(jsonEncode({'kind': 'rate', 'data': rate}));
    }

    return lines.join('\n');
  }
}
