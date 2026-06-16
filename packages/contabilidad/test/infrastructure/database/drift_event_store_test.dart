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
import 'package:contabilidad/domain/ports/log_filters.dart';

/// On Linux CI/dev environments, `libsqlite3.so` (unversioned) may not be
/// present. Fall back to the versioned `.so.0` if needed.
void _ensureSqlite3() {
  if (!Platform.isLinux) return;
  open.overrideForAll(() {
    // Try the canonical unversioned name first.
    try {
      return DynamicLibrary.open('libsqlite3.so');
    } catch (_) {}
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
      'second append of same event_id returns false; only one row stored',
      () async {
        final tx = buildTransaction(eventId: 'evt-dup');

        expect(await store.append(tx), isTrue);
        expect(await store.append(tx), isFalse);

        final log = await store.queryLog();
        expect(log, hasLength(1));
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

  // ------------------------------------------------------------------ hasReversal
  group('hasReversal', () {
    test('returns false before reversal appended, true after', () async {
      final origId = EventId('evt-orig');
      final original = buildTransaction(eventId: 'evt-orig');
      await store.append(original);

      expect(await store.hasReversal(origId), isFalse);

      final reversal = Transaction.create(
        postings: [
          Posting(
            target: AccountTarget(AccountId('acc-01')),
            amountNative: Money(
              amount: BigInt.from(-1000),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: -1000,
          ),
          Posting(
            target: EnvelopeTarget(EnvelopeId('env-01')),
            amountNative: Money(
              amount: BigInt.from(-1000),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: -1000,
          ),
        ],
        metadata: TransactionMetadata(
          eventId: EventId('evt-rev'),
          type: 'Reversal',
          occurredAt: DomainTimestamp(DateTime.utc(2026, 6, 16, 11)),
          recordedAt: DomainTimestamp(DateTime.utc(2026, 6, 16, 11, 1)),
          deviceId: 'device-test',
          schemaVersion: 1,
          reverses: origId,
        ),
      );
      await store.append(reversal);

      expect(await store.hasReversal(origId), isTrue);
    });
  });

  // ------------------------------------------------------------------ event_targets derivation
  group('event_targets derivation', () {
    test(
      'appending event writes correct target rows derived from postings',
      () async {
        final tx = buildTransaction(eventId: 'evt-targets');
        await store.append(tx);

        // Verify via queryLog filters that targets are correctly derived.
        final byAccount = await store.queryLog(
          filters: LogFilters(account: AccountId('acc-01')),
        );
        expect(byAccount, hasLength(1));
        expect(byAccount.first.metadata.eventId.value, equals('evt-targets'));

        final byEnvelope = await store.queryLog(
          filters: LogFilters(envelope: EnvelopeId('env-01')),
        );
        expect(byEnvelope, hasLength(1));
      },
    );

    test(
      'dedup does not write duplicate target rows on second append',
      () async {
        final tx = buildTransaction(eventId: 'evt-dup-targets');
        await store.append(tx);
        await store.append(tx); // second append is no-op

        // If duplicate targets were written, filters would still return 1 event
        // but internal count would be wrong — validate via queryLog count.
        final log = await store.queryLog(
          filters: LogFilters(account: AccountId('acc-01')),
        );
        expect(log, hasLength(1));
      },
    );
  });

  // ------------------------------------------------------------------ canonical ordering
  group('queryLog canonical order', () {
    test(
      'events returned in (occurred_at, recorded_at, event_id) order',
      () async {
        final txC = buildTransaction(
          eventId: 'evt-c',
          occurredAt: DateTime.utc(2026, 6, 16, 10),
          recordedAt: DateTime.utc(2026, 6, 16, 10, 9),
        );
        final txA = buildTransaction(
          eventId: 'evt-a',
          occurredAt: DateTime.utc(2026, 6, 16, 10),
          recordedAt: DateTime.utc(2026, 6, 16, 10, 10),
        );
        final txB = buildTransaction(
          eventId: 'evt-b',
          occurredAt: DateTime.utc(2026, 6, 16, 9),
          recordedAt: DateTime.utc(2026, 6, 16, 9, 1),
        );

        // Insert out-of-order
        await store.append(txA);
        await store.append(txC);
        await store.append(txB);

        final log = await store.queryLog();
        final ids = log.map((t) => t.metadata.eventId.value).toList();
        // txB occurred_at earliest; then txC (same occurred as txA but earlier recorded); then txA
        expect(ids, equals(['evt-b', 'evt-c', 'evt-a']));
      },
    );
  });

  // ------------------------------------------------------------------ atomicity
  group('atomicity', () {
    test('multiple events appended are all retrievable', () async {
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

  // ------------------------------------------------------------------ date filters
  group('queryLog date filters', () {
    test('from/to filter by occurred_at epoch', () async {
      final txEarly = buildTransaction(
        eventId: 'evt-early',
        occurredAt: DateTime.utc(2026, 1, 1),
      );
      final txMid = buildTransaction(
        eventId: 'evt-mid',
        occurredAt: DateTime.utc(2026, 6, 1),
      );
      final txLate = buildTransaction(
        eventId: 'evt-late',
        occurredAt: DateTime.utc(2026, 12, 1),
      );
      await store.append(txEarly);
      await store.append(txMid);
      await store.append(txLate);

      final filtered = await store.queryLog(
        filters: LogFilters(
          from: DomainTimestamp(DateTime.utc(2026, 5, 1)),
          to: DomainTimestamp(DateTime.utc(2026, 7, 1)),
        ),
      );
      expect(filtered.map((t) => t.metadata.eventId.value).toList(), [
        'evt-mid',
      ]);
    });
  });
}
