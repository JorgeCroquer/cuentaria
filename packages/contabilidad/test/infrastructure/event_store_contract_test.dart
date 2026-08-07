/// Parametrized contract/parity suite for [EventStore].
///
/// Runs the SAME behavioral contract against:
///   - [InMemoryEventStore]   (reference implementation)
///   - [DriftEventStore]      (Drift/SQLite adapter)
///
/// If both pass identically, the swap is safe by construction (F2 guarantee).
///
/// Covers (slice #43 acceptance criteria):
///   - append + dedup by event_id (from slice #42, verified here for parity)
///   - get
///   - queryLog: canonical order (occurred_at → recorded_at → event_id)
///   - queryLog: filter by account
///   - queryLog: filter by envelope
///   - queryLog: filter by date range (from / to / both)
///   - queryLog: combined filters
///   - queryLog: empty result cases
///   - hasReversal: false before reversal, true after
///   - hasReversal: unknown id returns false
library;

import 'dart:ffi';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:sqlite3/open.dart';
import 'package:test/test.dart';
import 'package:shared_kernel/shared_kernel.dart';

import 'package:contabilidad/domain/ports/event_store.dart';
import 'package:contabilidad/domain/ports/log_filters.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:contabilidad/infrastructure/codec/event_codec.dart';
import 'package:contabilidad/infrastructure/database/cuentaria_database.dart';
import 'package:contabilidad/infrastructure/database/drift_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';

// ---------------------------------------------------------------------------
// SQLite3 setup for Linux/WSL
// ---------------------------------------------------------------------------

void _ensureSqlite3() {
  if (!Platform.isLinux) return;
  open.overrideForAll(() {
    try {
      return DynamicLibrary.open('libsqlite3.so');
    } catch (_) {
      // ignore: empty_catches
    }
    return DynamicLibrary.open('libsqlite3.so.0');
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Minimal valid [Transaction] builder.
Transaction makeTx({
  required String eventId,
  String type = 'Test',
  DateTime? occurredAt,
  DateTime? recordedAt,
  AccountId? accountId,
  EnvelopeId? envelopeId,
  EventId? reverses,
}) {
  final occurred = occurredAt ?? DateTime.utc(2026, 6, 16, 10);
  final recorded = recordedAt ?? DateTime.utc(2026, 6, 16, 10, 1);
  final accId = accountId ?? AccountId('acc-default');
  final envId = envelopeId ?? EnvelopeId('env-default');

  return Transaction.create(
    metadata: TransactionMetadata(
      eventId: EventId(eventId),
      type: type,
      occurredAt: DomainTimestamp(occurred),
      recordedAt: DomainTimestamp(recorded),
      deviceId: 'device-test',
      schemaVersion: 1,
      reverses: reverses,
    ),
    postings: [
      Posting(
        target: AccountTarget(accId),
        amountNative: Money(
          amount: BigInt.from(100),
          currency: CurrencyCode('USD'),
        ),
        currency: CurrencyCode('USD'),
        amountUsd: 100,
      ),
      Posting(
        target: EnvelopeTarget(envId),
        amountNative: Money(
          amount: BigInt.from(100),
          currency: CurrencyCode('USD'),
        ),
        currency: CurrencyCode('USD'),
        amountUsd: 100,
      ),
    ],
  );
}

List<String> ids(List<Transaction> txs) =>
    txs.map((t) => t.metadata.eventId.value).toList();

// ---------------------------------------------------------------------------
// Contract suite — parametrized over a factory
// ---------------------------------------------------------------------------

typedef _Factory = Future<EventStore> Function();
typedef _Teardown = Future<void> Function();

/// Runs the full contract suite against one [EventStore] implementation.
void runEventStoreContract(
  String label,
  _Factory makeStore, {
  _Teardown? teardown,
}) {
  group('EventStore contract [$label]', () {
    late EventStore store;

    setUp(() async {
      store = await makeStore();
    });

    tearDown(() async {
      await teardown?.call();
    });

    // ------------------------------------------------------------------ append + dedup
    group('append + dedup', () {
      test('returns true on new event', () async {
        final tx = makeTx(eventId: 'evt-new');
        expect(await store.append(tx), isTrue);
      });

      test('returns false on duplicate event_id', () async {
        final tx = makeTx(eventId: 'evt-dup');
        await store.append(tx);
        expect(await store.append(tx), isFalse);
      });

      test('duplicate does not store extra copies', () async {
        final tx = makeTx(eventId: 'evt-dup2');
        await store.append(tx);
        await store.append(tx);
        final log = await store.queryLog();
        expect(
          log.where((t) => t.metadata.eventId.value == 'evt-dup2'),
          hasLength(1),
        );
      });
    });

    // ------------------------------------------------------------------ get
    group('get', () {
      test('returns transaction after append', () async {
        final tx = makeTx(eventId: 'evt-get');
        await store.append(tx);
        final result = await store.get(EventId('evt-get'));
        expect(result, isNotNull);
        expect(result!.metadata.eventId.value, equals('evt-get'));
      });

      test('returns null for unknown id', () async {
        expect(await store.get(EventId('no-such-id')), isNull);
      });
    });

    // ------------------------------------------------------------------ queryLog order
    group('queryLog — canonical order', () {
      test('events ordered by (occurredAt, recordedAt, eventId)', () async {
        // txB: occurred=June1 → first
        // txC: occurred=June3, recorded=June9 → second
        // txA: occurred=June3, recorded=June10 → third
        final txA = makeTx(
          eventId: 'evt-a',
          occurredAt: DateTime.utc(2026, 6, 3),
          recordedAt: DateTime.utc(2026, 6, 10),
        );
        final txB = makeTx(
          eventId: 'evt-b',
          occurredAt: DateTime.utc(2026, 6, 1),
          recordedAt: DateTime.utc(2026, 6, 11),
        );
        final txC = makeTx(
          eventId: 'evt-c',
          occurredAt: DateTime.utc(2026, 6, 3),
          recordedAt: DateTime.utc(2026, 6, 9),
        );

        // Insert out of order to prove sorting, not insertion order.
        await store.append(txC);
        await store.append(txA);
        await store.append(txB);

        final result = await store.queryLog();
        expect(ids(result), equals(['evt-b', 'evt-c', 'evt-a']));
      });

      test(
        'tie on occurredAt+recordedAt resolved by eventId lexicographic',
        () async {
          final base = DateTime.utc(2026, 6, 16, 12);
          final txZ = makeTx(
            eventId: 'evt-zzz',
            occurredAt: base,
            recordedAt: base,
          );
          final txA = makeTx(
            eventId: 'evt-aaa',
            occurredAt: base,
            recordedAt: base,
          );
          final txM = makeTx(
            eventId: 'evt-mmm',
            occurredAt: base,
            recordedAt: base,
          );

          await store.append(txZ);
          await store.append(txA);
          await store.append(txM);

          final result = await store.queryLog();
          expect(ids(result), equals(['evt-aaa', 'evt-mmm', 'evt-zzz']));
        },
      );

      test('empty store returns empty list', () async {
        expect(await store.queryLog(), isEmpty);
      });
    });

    // ------------------------------------------------------------------ queryLog filter by account
    group('queryLog — filter by account', () {
      test('returns only events touching that account', () async {
        final acc1 = AccountId('acc-1');
        final acc2 = AccountId('acc-2');

        final tx1 = makeTx(
          eventId: 'evt-acc1-a',
          accountId: acc1,
          occurredAt: DateTime.utc(2026, 6, 1),
        );
        final tx2 = makeTx(
          eventId: 'evt-acc2',
          accountId: acc2,
          occurredAt: DateTime.utc(2026, 6, 2),
        );
        final tx3 = makeTx(
          eventId: 'evt-acc1-b',
          accountId: acc1,
          occurredAt: DateTime.utc(2026, 6, 3),
        );

        await store.append(tx1);
        await store.append(tx2);
        await store.append(tx3);

        final result = await store.queryLog(filters: LogFilters(account: acc1));
        expect(ids(result).toSet(), equals({'evt-acc1-a', 'evt-acc1-b'}));
      });

      test('returns empty list when no events touch that account', () async {
        await store.append(
          makeTx(eventId: 'evt-other', accountId: AccountId('acc-x')),
        );
        final result = await store.queryLog(
          filters: LogFilters(account: AccountId('acc-nobody')),
        );
        expect(result, isEmpty);
      });
    });

    // ------------------------------------------------------------------ queryLog filter by envelope
    group('queryLog — filter by envelope', () {
      test('returns only events touching that envelope', () async {
        final env1 = EnvelopeId('env-1');
        final env2 = EnvelopeId('env-2');

        final tx1 = makeTx(
          eventId: 'evt-env1',
          envelopeId: env1,
          occurredAt: DateTime.utc(2026, 6, 1),
        );
        final tx2 = makeTx(
          eventId: 'evt-env2',
          envelopeId: env2,
          occurredAt: DateTime.utc(2026, 6, 2),
        );

        await store.append(tx1);
        await store.append(tx2);

        final result = await store.queryLog(
          filters: LogFilters(envelope: env1),
        );
        expect(ids(result), equals(['evt-env1']));
      });

      test('returns empty list when no events touch that envelope', () async {
        await store.append(
          makeTx(eventId: 'evt-other', envelopeId: EnvelopeId('env-x')),
        );
        final result = await store.queryLog(
          filters: LogFilters(envelope: EnvelopeId('env-nobody')),
        );
        expect(result, isEmpty);
      });
    });

    // ------------------------------------------------------------------ queryLog filter by date range
    group('queryLog — filter by date range', () {
      test('from filter: includes events at or after cutoff', () async {
        final cutoff = DomainTimestamp(DateTime.utc(2026, 6, 5));
        await store.append(
          makeTx(eventId: 'evt-before', occurredAt: DateTime.utc(2026, 6, 4)),
        );
        await store.append(
          makeTx(eventId: 'evt-at', occurredAt: DateTime.utc(2026, 6, 5)),
        );
        await store.append(
          makeTx(eventId: 'evt-after', occurredAt: DateTime.utc(2026, 6, 6)),
        );

        final result = await store.queryLog(filters: LogFilters(from: cutoff));
        expect(ids(result).toSet(), equals({'evt-at', 'evt-after'}));
      });

      test('to filter: includes events at or before cutoff', () async {
        final cutoff = DomainTimestamp(DateTime.utc(2026, 6, 5));
        await store.append(
          makeTx(eventId: 'evt-before', occurredAt: DateTime.utc(2026, 6, 4)),
        );
        await store.append(
          makeTx(eventId: 'evt-at', occurredAt: DateTime.utc(2026, 6, 5)),
        );
        await store.append(
          makeTx(eventId: 'evt-after', occurredAt: DateTime.utc(2026, 6, 6)),
        );

        final result = await store.queryLog(filters: LogFilters(to: cutoff));
        expect(ids(result).toSet(), equals({'evt-before', 'evt-at'}));
      });

      test(
        'from+to range: returns only events within inclusive bounds',
        () async {
          await store.append(
            makeTx(eventId: 'evt-d1', occurredAt: DateTime.utc(2026, 6, 1)),
          );
          await store.append(
            makeTx(eventId: 'evt-d5', occurredAt: DateTime.utc(2026, 6, 5)),
          );
          await store.append(
            makeTx(eventId: 'evt-d10', occurredAt: DateTime.utc(2026, 6, 10)),
          );

          final result = await store.queryLog(
            filters: LogFilters(
              from: DomainTimestamp(DateTime.utc(2026, 6, 4)),
              to: DomainTimestamp(DateTime.utc(2026, 6, 6)),
            ),
          );
          expect(ids(result), equals(['evt-d5']));
        },
      );
    });

    // ------------------------------------------------------------------ queryLog combined filters
    group('queryLog — combined filters', () {
      test('account + envelope narrows to events touching both', () async {
        final acc1 = AccountId('acc-1');
        final env1 = EnvelopeId('env-1');
        final env2 = EnvelopeId('env-2');

        final tx1 = makeTx(
          eventId: 'evt-both',
          accountId: acc1,
          envelopeId: env1,
          occurredAt: DateTime.utc(2026, 6, 1),
        );
        final tx2 = makeTx(
          eventId: 'evt-acc-only',
          accountId: acc1,
          envelopeId: env2,
          occurredAt: DateTime.utc(2026, 6, 2),
        );

        await store.append(tx1);
        await store.append(tx2);

        final result = await store.queryLog(
          filters: LogFilters(account: acc1, envelope: env1),
        );
        expect(ids(result), equals(['evt-both']));
      });

      test('account + date range applies both predicates', () async {
        final acc1 = AccountId('acc-1');
        await store.append(
          makeTx(
            eventId: 'evt-acc-early',
            accountId: acc1,
            occurredAt: DateTime.utc(2026, 6, 1),
          ),
        );
        await store.append(
          makeTx(
            eventId: 'evt-acc-late',
            accountId: acc1,
            occurredAt: DateTime.utc(2026, 6, 20),
          ),
        );
        await store.append(
          makeTx(
            eventId: 'evt-other-mid',
            accountId: AccountId('acc-2'),
            occurredAt: DateTime.utc(2026, 6, 10),
          ),
        );

        final result = await store.queryLog(
          filters: LogFilters(
            account: acc1,
            from: DomainTimestamp(DateTime.utc(2026, 6, 15)),
          ),
        );
        expect(ids(result), equals(['evt-acc-late']));
      });
    });

    // ------------------------------------------------------------------ hasReversal
    group('hasReversal', () {
      test('returns false for unknown original id', () async {
        expect(await store.hasReversal(EventId('evt-nobody')), isFalse);
      });

      test(
        'returns false when original exists but no reversal appended',
        () async {
          await store.append(makeTx(eventId: 'evt-orig'));
          expect(await store.hasReversal(EventId('evt-orig')), isFalse);
        },
      );

      test('returns true after a reversing event is appended', () async {
        final origId = EventId('evt-orig');
        await store.append(makeTx(eventId: origId.value));
        await store.append(
          makeTx(eventId: 'evt-rev', reverses: origId, type: 'Reversal'),
        );
        expect(await store.hasReversal(origId), isTrue);
      });

      test('reversal of A does not affect hasReversal(B)', () async {
        final idA = EventId('evt-a');
        final idB = EventId('evt-b');
        await store.append(makeTx(eventId: idA.value));
        await store.append(makeTx(eventId: idB.value));
        await store.append(
          makeTx(eventId: 'evt-rev-a', reverses: idA, type: 'Reversal'),
        );
        expect(await store.hasReversal(idA), isTrue);
        expect(await store.hasReversal(idB), isFalse);
      });
    });

    // ------------------------------------------------------------------ queryRawPayloads
    group('queryRawPayloads', () {
      const codec = EventCodec();

      test(
        'returns the exact stored payload, not a decode/re-encode round-trip',
        () async {
          final tx = makeTx(eventId: 'evt-raw');
          await store.append(tx);

          final payloads = await store.queryRawPayloads();
          expect(payloads, equals([codec.encode(tx)]));
        },
      );

      test(
        'canonical order matches queryLog: (occurredAt, recordedAt, eventId)',
        () async {
          final txA = makeTx(
            eventId: 'evt-a',
            occurredAt: DateTime.utc(2026, 6, 3),
            recordedAt: DateTime.utc(2026, 6, 10),
          );
          final txB = makeTx(
            eventId: 'evt-b',
            occurredAt: DateTime.utc(2026, 6, 1),
          );
          final txC = makeTx(
            eventId: 'evt-c',
            occurredAt: DateTime.utc(2026, 6, 3),
            recordedAt: DateTime.utc(2026, 6, 9),
          );

          await store.append(txC);
          await store.append(txA);
          await store.append(txB);

          final payloads = await store.queryRawPayloads();
          expect(
            payloads.map(codec.decode).map((t) => t.metadata.eventId.value),
            equals(['evt-b', 'evt-c', 'evt-a']),
          );
        },
      );

      test('applies the same account filter as queryLog', () async {
        final acc1 = AccountId('acc-1');
        final acc2 = AccountId('acc-2');
        await store.append(makeTx(eventId: 'evt-acc1', accountId: acc1));
        await store.append(makeTx(eventId: 'evt-acc2', accountId: acc2));

        final payloads = await store.queryRawPayloads(
          filters: LogFilters(account: acc1),
        );
        expect(
          payloads.map(codec.decode).map((t) => t.metadata.eventId.value),
          equals(['evt-acc1']),
        );
      });

      test('empty store returns empty list', () async {
        expect(await store.queryRawPayloads(), isEmpty);
      });
    });
  });
}

// ---------------------------------------------------------------------------
// Wire up both adapters
// ---------------------------------------------------------------------------

void main() {
  setUpAll(_ensureSqlite3);

  // In-memory adapter — stateless, no teardown needed.
  runEventStoreContract('InMemoryEventStore', () async => InMemoryEventStore());

  // Drift adapter — fresh in-memory SQLite per test run; teardown closes DB.
  late CuentariaDatabase _db;

  runEventStoreContract('DriftEventStore', () async {
    _db = CuentariaDatabase(NativeDatabase.memory());
    return DriftEventStore(_db);
  }, teardown: () async => _db.close());
}
