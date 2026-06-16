import 'dart:ffi';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:sqlite3/open.dart';
import 'package:test/test.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:contabilidad/infrastructure/database/cuentaria_database.dart';
import 'package:contabilidad/infrastructure/database/drift_event_store.dart';

/// On Linux CI/dev environments, `libsqlite3.so` (unversioned) may not be
/// present. Fall back to the versioned `.so.0` if needed.
/// WSL / Debian-like systems ship only `libsqlite3.so.0` without the dev
/// symlink; the catch swallows the open error from the first attempt so we can
/// retry with the versioned name.
void _ensureSqlite3() {
  if (!Platform.isLinux) return;
  open.overrideForAll(() {
    // Try the canonical unversioned name first.
    try {
      return DynamicLibrary.open('libsqlite3.so');
    } catch (_) {
      // ignore: empty_catches — unversioned .so absent on WSL/Debian; try .so.0
    }
    // WSL / Debian-like systems ship libsqlite3.so.0 without the dev symlink.
    return DynamicLibrary.open('libsqlite3.so.0');
  });
}

/// Builds a minimal valid Transaction for test use.
Transaction buildTransaction({
  String eventId = 'evt-001',
  String type = 'Income',
  DateTime? occurredAt,
  DateTime? recordedAt,
  String deviceId = 'device-test',
  EventId? reverses,
}) {
  final ts = occurredAt ?? DateTime.utc(2026, 6, 16, 10, 0);
  final rec = recordedAt ?? DateTime.utc(2026, 6, 16, 10, 1);
  final meta = TransactionMetadata(
    eventId: EventId(eventId),
    type: type,
    occurredAt: DomainTimestamp(ts),
    recordedAt: DomainTimestamp(rec),
    deviceId: deviceId,
    schemaVersion: 1,
    reverses: reverses,
  );
  return Transaction.create(
    postings: [
      Posting(
        target: AccountTarget(AccountId('acc-01')),
        amountNative: Money(
          amount: BigInt.from(1000),
          currency: CurrencyCode('USD'),
        ),
        currency: CurrencyCode('USD'),
        amountUsd: 1000,
      ),
      Posting(
        target: EnvelopeTarget(EnvelopeId('env-01')),
        amountNative: Money(
          amount: BigInt.from(1000),
          currency: CurrencyCode('USD'),
        ),
        currency: CurrencyCode('USD'),
        amountUsd: 1000,
      ),
    ],
    metadata: meta,
  );
}

void main() {
  setUpAll(_ensureSqlite3);

  late CuentariaDatabase db;
  late DriftEventStore store;

  setUp(() {
    db = CuentariaDatabase(NativeDatabase.memory());
    store = DriftEventStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  // ------------------------------------------------------------------ tracer
  group('append + get round-trip', () {
    test(
      'append returns true on new event; get returns equal Transaction',
      () async {
        final tx = buildTransaction(eventId: 'evt-round-trip');

        final inserted = await store.append(tx);
        expect(inserted, isTrue);

        final retrieved = await store.get(EventId('evt-round-trip'));
        expect(retrieved, isNotNull);
        expect(retrieved, equals(tx));
      },
    );
  });

  // ------------------------------------------------------------------ dedup
  group('dedup by event_id', () {
    test(
      'second append of same event_id returns false without throwing',
      () async {
        final tx = buildTransaction(eventId: 'evt-dup');

        expect(await store.append(tx), isTrue);
        // Must return false, not throw, not mutate.
        expect(await store.append(tx), isFalse);
      },
    );

    test('duplicate append does not create extra rows', () async {
      final tx = buildTransaction(eventId: 'evt-dup-rows');
      await store.append(tx);
      await store.append(tx);

      // Only one row stored — verify via get (row exists) and by checking that
      // a third append still returns false.
      final retrieved = await store.get(EventId('evt-dup-rows'));
      expect(retrieved, isNotNull);
      expect(await store.append(tx), isFalse);
    });

    test(
      'concurrent-like duplicate: second call returns false atomically',
      () async {
        final tx = buildTransaction(eventId: 'evt-concurrent-dup');
        final results = await Future.wait([store.append(tx), store.append(tx)]);
        // Exactly one true, one false (order may vary).
        expect(results.where((r) => r).length, equals(1));
        expect(results.where((r) => !r).length, equals(1));
      },
    );
  });

  // ------------------------------------------------------------------ get missing
  group('get missing', () {
    test('get returns null for unknown event_id', () async {
      final result = await store.get(EventId('no-such-event'));
      expect(result, isNull);
    });
  });

  // ------------------------------------------------------------------ atomicity
  group('atomicity', () {
    test('multiple distinct events are all retrievable', () async {
      final tx1 = buildTransaction(
        eventId: 'evt-atom-a',
        occurredAt: DateTime.utc(2026, 6, 16, 9),
        recordedAt: DateTime.utc(2026, 6, 16, 9, 1),
      );
      final tx2 = buildTransaction(
        eventId: 'evt-atom-b',
        occurredAt: DateTime.utc(2026, 6, 16, 10),
        recordedAt: DateTime.utc(2026, 6, 16, 10, 1),
      );
      await store.append(tx1);
      await store.append(tx2);

      expect(await store.get(EventId('evt-atom-a')), isNotNull);
      expect(await store.get(EventId('evt-atom-b')), isNotNull);
    });
  });

  // ------------------------------------------------------------------ event_targets derivation
  group('event_targets derivation', () {
    test('append writes one account + one envelope target row', () async {
      final tx = buildTransaction(eventId: 'evt-targets');
      await store.append(tx);

      final rows = await db.select(db.eventTargets).get();
      expect(rows, hasLength(2));

      final dimensions = rows.map((r) => r.dimension).toSet();
      expect(dimensions, containsAll(['account', 'envelope']));

      final accountRow = rows.firstWhere((r) => r.dimension == 'account');
      expect(accountRow.targetId, equals('acc-01'));
      expect(accountRow.eventId, equals('evt-targets'));

      final envelopeRow = rows.firstWhere((r) => r.dimension == 'envelope');
      expect(envelopeRow.targetId, equals('env-01'));
    });

    test('duplicate append does not write duplicate target rows', () async {
      final tx = buildTransaction(eventId: 'evt-dup-targets');
      await store.append(tx);
      await store.append(tx); // no-op

      final rows = await db.select(db.eventTargets).get();
      // Still exactly 2 rows (account + envelope), not 4.
      expect(rows, hasLength(2));
    });
  });
}
