import 'package:backup/backup.dart';
import 'package:test/test.dart';

void main() {
  group('Event byte-identity', () {
    test('an event payload with an old schema_version survives unchanged', () {
      const writer = BackupWriter();
      const reader = BackupReader();

      // Canonical JSON as EventCodec would have produced it for a v1 event —
      // note the alphabetically-sorted keys and complete absence of whitespace.
      const oldPayload =
          '{"amount_usd":1000,"event_id":"evt-legacy","occurred_at":'
          '"2026-01-01T00:00:00.000Z","schema_version":1,"type":"Income"}';

      final ndjson = writer.write(
        exportedAt: DateTime.utc(2026, 8, 7),
        events: [oldPayload],
      );

      final file = reader.parse(ndjson);

      // Byte-for-byte identical: not just "equivalent JSON" after a
      // decode/re-encode round-trip, which could reorder keys or add
      // whitespace and would defeat the point of this guarantee.
      expect(file.events.single, equals(oldPayload));
      expect(file.events.single.codeUnits, equals(oldPayload.codeUnits));
    });

    test('event lines are concatenated as opaque text, never re-encoded', () {
      const writer = BackupWriter();

      // Deliberately contains a raw unicode character and unusual (but
      // valid, canonical) formatting choices that a naive re-encode could
      // normalize away.
      const payload = '{"event_id":"evt-ñ","type":"Transferencia"}';

      final ndjson = writer.write(
        exportedAt: DateTime.utc(2026, 8, 7),
        events: [payload],
      );

      final eventLine = ndjson.split('\n')[1];
      expect(eventLine, equals('{"kind":"event","data":$payload}'));
    });
  });
}
