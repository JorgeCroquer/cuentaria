import 'package:backup/backup.dart';
import 'package:test/test.dart';

void main() {
  group('BackupWriter/BackupReader round-trip', () {
    test('writes and reads back all five line classes', () {
      const writer = BackupWriter();
      const reader = BackupReader();

      final exportedAt = DateTime.utc(2026, 8, 7, 14, 3);
      final account = {
        'id': 'acc-1',
        'name': 'Efectivo',
        'nativeCurrency': 'USD',
        'isArchived': false,
        'updatedAt': '2026-08-01T00:00:00.000Z',
        'meta': {'color': '#00FF00'},
      };
      final envelope = {
        'id': 'env-1',
        'name': 'Alquiler',
        'role': 'none',
        'isArchived': false,
        'updatedAt': '2026-08-02T00:00:00.000Z',
        'meta': {
          'target': {'type': 'cap', 'amount_usd': 50000},
        },
      };
      final cascade = {
        'steps': ['env-1'],
        'updatedAt': '2026-08-03T00:00:00.000Z',
      };
      const eventPayload =
          '{"event_id":"evt-1","schema_version":1,"type":"Income"}';
      final rate = {
        'currency': 'VES',
        'source': 'bcv',
        'value': '36.50',
        'observedAt': '2026-08-06T00:00:00.000Z',
      };

      final ndjson = writer.write(
        exportedAt: exportedAt,
        accounts: [account],
        envelopes: [envelope],
        cascades: [cascade],
        events: [eventPayload],
        rates: [rate],
      );

      final file = reader.parse(ndjson);

      expect(file.header.format, equals(backupFormatVersion));
      expect(file.header.app, equals('cuentaria'));
      expect(file.header.exportedAt, equals(exportedAt));
      expect(
        file.header.counts,
        equals(
          const BackupCounts(
            event: 1,
            account: 1,
            envelope: 1,
            cascade: 1,
            rate: 1,
          ),
        ),
      );

      expect(file.accounts, equals([account]));
      expect(file.envelopes, equals([envelope]));
      expect(file.cascades, equals([cascade]));
      expect(file.events, equals([eventPayload]));
      expect(file.rates, equals([rate]));
    });

    test(
      'lines appear in canonical order: header, account, envelope, cascade, event, rate',
      () {
        const writer = BackupWriter();
        final ndjson = writer.write(
          exportedAt: DateTime.utc(2026, 1, 1),
          accounts: [
            {'id': 'a'},
          ],
          envelopes: [
            {'id': 'e'},
          ],
          cascades: [
            {'id': 'c'},
          ],
          events: ['{"event_id":"x"}'],
          rates: [
            {'id': 'r'},
          ],
        );

        final lines = ndjson.split('\n');
        expect(lines, hasLength(6));
        expect(lines[0], contains('"kind":"header"'));
        expect(lines[1], contains('"kind":"account"'));
        expect(lines[2], contains('"kind":"envelope"'));
        expect(lines[3], contains('"kind":"cascade"'));
        expect(lines[4], contains('"kind":"event"'));
        expect(lines[5], contains('"kind":"rate"'));
      },
    );

    test('empty backup has zero counts and only a header line', () {
      const writer = BackupWriter();
      const reader = BackupReader();

      final ndjson = writer.write(exportedAt: DateTime.utc(2026, 1, 1));
      expect(ndjson.split('\n'), hasLength(1));

      final file = reader.parse(ndjson);
      expect(
        file.header.counts,
        equals(
          const BackupCounts(
            event: 0,
            account: 0,
            envelope: 0,
            cascade: 0,
            rate: 0,
          ),
        ),
      );
      expect(file.accounts, isEmpty);
    });

    test('rejects a file with an unknown format version', () {
      const reader = BackupReader();
      final ndjson =
          '{"kind":"header","format":999,"app":"cuentaria",'
          '"exportedAt":"2026-01-01T00:00:00.000Z",'
          '"counts":{"event":0,"account":0,"envelope":0,"cascade":0,"rate":0}}';

      expect(() => reader.parse(ndjson), throwsA(isA<UnknownFormatVersion>()));
    });
  });
}
