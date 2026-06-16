/// Integration tests for boot hydration — the replay backbone (F2 Slice 5).
///
/// Seam under test: RebuildProjections ↔ DriftEventStore ↔ LedgerProjections
///                  DriftCatalogRepository.hydrate() ↔ CuentariaDatabase
///
/// Verifies F2-1/F2-9 decisions:
///   - On boot, projections are rebuilt by replaying the Drift log in canonical
///     order; catalog cache is hydrated.
///   - Reconstructed balances equal incrementally-maintained balances.
///   - Zero-native rule holds after replay (C1-6).
///   - Reversal nets to zero after replay (C1-10).
///   - Killing after a durable append and re-replaying reproduces same balances.
library;

import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/ledger/rebuild_projections.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:contabilidad/infrastructure/catalog/drift_catalog_repository.dart';
import 'package:contabilidad/infrastructure/database/cuentaria_database.dart';
import 'package:contabilidad/infrastructure/database/drift_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:test/test.dart';

import '../../infrastructure/catalog/test_helpers.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Transaction _buildTx({
  required String eventId,
  required String accountId,
  required String envelopeId,
  required int amountUsd,
  required String currency,
  DateTime? occurredAt,
  DateTime? recordedAt,
  EventId? reverses,
}) {
  final now = DateTime.utc(2026, 6, 16, 10, 0);
  return Transaction.create(
    metadata: TransactionMetadata(
      eventId: EventId(eventId),
      type: 'Test',
      occurredAt: DomainTimestamp(occurredAt ?? now),
      recordedAt: DomainTimestamp(recordedAt ?? now),
      deviceId: 'device-test',
      schemaVersion: 1,
      reverses: reverses,
    ),
    postings: [
      Posting(
        target: AccountTarget(AccountId(accountId)),
        amountNative: Money(
          amount: BigInt.from(amountUsd),
          currency: CurrencyCode(currency),
        ),
        currency: CurrencyCode(currency),
        amountUsd: amountUsd,
      ),
      Posting(
        target: EnvelopeTarget(EnvelopeId(envelopeId)),
        amountNative: Money(
          amount: BigInt.from(amountUsd),
          currency: CurrencyCode(currency),
        ),
        currency: CurrencyCode(currency),
        amountUsd: amountUsd,
      ),
    ],
  );
}

/// Simulates a "reopen" by building fresh RebuildProjections on the same DB.
Future<InMemoryLedgerProjections> _replay(CuentariaDatabase db) async {
  final store = DriftEventStore(db);
  final projections = InMemoryLedgerProjections();
  await RebuildProjections(store: store, projections: projections).execute();
  return projections;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late CuentariaDatabase db;

  setUpAll(ensureSqlite3);

  setUp(() {
    db = openTestDb();
  });

  tearDown(() => db.close());

  group('Boot hydration — RebuildProjections over DriftEventStore', () {
    test(
      'replay over Drift reconstructs same balances as incremental application',
      () async {
        final store = DriftEventStore(db);
        final incremental = InMemoryLedgerProjections();

        final tx1 = _buildTx(
          eventId: 'replay-1',
          accountId: 'acc-a',
          envelopeId: 'env-a',
          amountUsd: 5000,
          currency: 'USD',
        );
        final tx2 = _buildTx(
          eventId: 'replay-2',
          accountId: 'acc-a',
          envelopeId: 'env-a',
          amountUsd: 3000,
          currency: 'USD',
        );

        await store.append(tx1);
        incremental.apply(tx1);
        await store.append(tx2);
        incremental.apply(tx2);

        final replayed = await _replay(db);

        expect(
          replayed.accountBalance(AccountId('acc-a')).usd,
          equals(incremental.accountBalance(AccountId('acc-a')).usd),
        );
        expect(
          replayed.accountBalance(AccountId('acc-a')).native.amount,
          equals(incremental.accountBalance(AccountId('acc-a')).native.amount),
        );
        expect(
          replayed.envelopeUsdBalance(EnvelopeId('env-a')),
          equals(incremental.envelopeUsdBalance(EnvelopeId('env-a'))),
        );
      },
    );

    test('replay reconstructs state when in-memory apply was skipped '
        '(best-effort path / crash simulation)', () async {
      // Append durable commit only — no in-memory apply (simulates crash
      // right after Drift commit, before best-effort path runs, F2-9-a).
      final store = DriftEventStore(db);

      final tx = _buildTx(
        eventId: 'crash-evt',
        accountId: 'acc-crash',
        envelopeId: 'env-crash',
        amountUsd: 9999,
        currency: 'USD',
      );

      await store.append(tx);
      // Intentionally NOT calling incremental.apply(tx)

      final replayed = await _replay(db);

      expect(replayed.accountBalance(AccountId('acc-crash')).usd, equals(9999));
      expect(
        replayed.envelopeUsdBalance(EnvelopeId('env-crash')),
        equals(9999),
      );
    });

    test(
      'zero-native rule holds after replay of account-emptying sequence',
      () async {
        final store = DriftEventStore(db);

        const bs = 'VES';
        const acc = 'acc-bs';
        const env = 'env-bs';

        final deposit = Transaction.create(
          metadata: TransactionMetadata(
            eventId: EventId('bs-deposit'),
            type: 'Income',
            occurredAt: DomainTimestamp(DateTime.utc(2026, 6, 16, 10, 0)),
            recordedAt: DomainTimestamp(DateTime.utc(2026, 6, 16, 10, 0)),
            deviceId: 'device-test',
            schemaVersion: 1,
          ),
          postings: [
            Posting(
              target: AccountTarget(AccountId(acc)),
              amountNative: Money(
                amount: BigInt.from(1000),
                currency: CurrencyCode(bs),
              ),
              currency: CurrencyCode(bs),
              amountUsd: 100,
            ),
            Posting(
              target: EnvelopeTarget(EnvelopeId(env)),
              amountNative: Money(
                amount: BigInt.from(1000),
                currency: CurrencyCode(bs),
              ),
              currency: CurrencyCode(bs),
              amountUsd: 100,
            ),
          ],
        );

        final disposal = Transaction.create(
          metadata: TransactionMetadata(
            eventId: EventId('bs-disposal'),
            type: 'Expense',
            occurredAt: DomainTimestamp(DateTime.utc(2026, 6, 16, 10, 1)),
            recordedAt: DomainTimestamp(DateTime.utc(2026, 6, 16, 10, 1)),
            deviceId: 'device-test',
            schemaVersion: 1,
          ),
          postings: [
            Posting(
              target: AccountTarget(AccountId(acc)),
              amountNative: Money(
                amount: BigInt.from(-1000),
                currency: CurrencyCode(bs),
              ),
              currency: CurrencyCode(bs),
              amountUsd: -100,
            ),
            Posting(
              target: EnvelopeTarget(EnvelopeId(env)),
              amountNative: Money(
                amount: BigInt.from(-1000),
                currency: CurrencyCode(bs),
              ),
              currency: CurrencyCode(bs),
              amountUsd: -100,
            ),
          ],
        );

        await store.append(deposit);
        await store.append(disposal);

        final replayed = await _replay(db);

        final balance = replayed.accountBalance(AccountId(acc));
        expect(balance.native.amount, equals(BigInt.zero));
        expect(balance.usd, equals(0));
        expect(replayed.envelopeUsdBalance(EnvelopeId(env)), equals(0));
      },
    );

    test('reversal nets to zero after replay', () async {
      final store = DriftEventStore(db);

      final original = _buildTx(
        eventId: 'orig-evt',
        accountId: 'acc-rev',
        envelopeId: 'env-rev',
        amountUsd: 7500,
        currency: 'USD',
      );
      final reversal = Transaction.create(
        metadata: TransactionMetadata(
          eventId: EventId('rev-evt'),
          type: 'Reversal',
          occurredAt: DomainTimestamp(DateTime.utc(2026, 6, 16, 10, 2)),
          recordedAt: DomainTimestamp(DateTime.utc(2026, 6, 16, 10, 2)),
          deviceId: 'device-test',
          schemaVersion: 1,
          reverses: EventId('orig-evt'),
        ),
        postings: [
          Posting(
            target: AccountTarget(AccountId('acc-rev')),
            amountNative: Money(
              amount: BigInt.from(-7500),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: -7500,
          ),
          Posting(
            target: EnvelopeTarget(EnvelopeId('env-rev')),
            amountNative: Money(
              amount: BigInt.from(-7500),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: -7500,
          ),
        ],
      );

      await store.append(original);
      await store.append(reversal);

      final replayed = await _replay(db);

      expect(replayed.accountBalance(AccountId('acc-rev')).usd, equals(0));
      expect(replayed.envelopeUsdBalance(EnvelopeId('env-rev')), equals(0));
    });

    test(
      'self-balancing: Σusd[Account] == Σusd[Envelope] after replay',
      () async {
        final store = DriftEventStore(db);

        for (var i = 1; i <= 5; i++) {
          final tx = _buildTx(
            eventId: 'bal-$i',
            accountId: 'acc-bal-${i % 2}',
            envelopeId: 'env-bal-${i % 3}',
            amountUsd: i * 1000,
            currency: 'USD',
          );
          await store.append(tx);
        }

        final replayed = await _replay(db);

        final accountSum =
            replayed.accountBalance(AccountId('acc-bal-0')).usd +
            replayed.accountBalance(AccountId('acc-bal-1')).usd;

        final envelopeSum =
            replayed.envelopeUsdBalance(EnvelopeId('env-bal-0')) +
            replayed.envelopeUsdBalance(EnvelopeId('env-bal-1')) +
            replayed.envelopeUsdBalance(EnvelopeId('env-bal-2'));

        expect(accountSum, equals(envelopeSum));
      },
    );

    test(
      'canonical order: backdated event replays identical to incremental',
      () async {
        final store = DriftEventStore(db);
        final incremental = InMemoryLedgerProjections();

        // Arrive in order day2→day3→day1 (backdated)
        final txDay2 = _buildTx(
          eventId: 'day2',
          accountId: 'acc-order',
          envelopeId: 'env-order',
          amountUsd: 200,
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 6, 2),
        );
        final txDay3 = _buildTx(
          eventId: 'day3',
          accountId: 'acc-order',
          envelopeId: 'env-order',
          amountUsd: 300,
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 6, 3),
        );
        final txDay1 = _buildTx(
          eventId: 'day1',
          accountId: 'acc-order',
          envelopeId: 'env-order',
          amountUsd: 100,
          currency: 'USD',
          occurredAt: DateTime.utc(2026, 6, 1),
        );

        await store.append(txDay2);
        incremental.apply(txDay2);
        await store.append(txDay3);
        incremental.apply(txDay3);
        await store.append(txDay1);
        incremental.apply(txDay1);

        final replayed = await _replay(db);

        // Sum is commutative (600); both paths must agree
        expect(
          replayed.accountBalance(AccountId('acc-order')).usd,
          equals(incremental.accountBalance(AccountId('acc-order')).usd),
        );
      },
    );
  });

  group('Boot hydration — DriftCatalogRepository', () {
    test('hydrate on fresh DB exposes all system envelopes', () async {
      final repo = DriftCatalogRepository(db);
      await repo.hydrate();

      expect(
        repo.getSystemEnvelope(EnvelopeRole.stage),
        equals(EnvelopeId('sys-stage')),
      );
      expect(
        repo.getSystemEnvelope(EnvelopeRole.opening),
        equals(EnvelopeId('sys-opening')),
      );
      expect(
        repo.getSystemEnvelope(EnvelopeRole.differential),
        equals(EnvelopeId('sys-differential')),
      );
      expect(
        repo.getSystemEnvelope(EnvelopeRole.adjustments),
        equals(EnvelopeId('sys-adjustments')),
      );
    });

    test(
      'account persisted in session 1 is visible after re-hydrate (session 2)',
      () async {
        final repo1 = DriftCatalogRepository(db);
        await repo1.hydrate();

        await repo1.saveAccount(
          Account(
            id: AccountId('acc-reopen'),
            name: 'Reopen Test',
            nativeCurrency: CurrencyCode('USD'),
            isArchived: false,
            updatedAt: DateTime.utc(2026, 6, 16),
          ),
        );

        // Fresh instance, same underlying DB
        final repo2 = DriftCatalogRepository(db);
        await repo2.hydrate();

        final found = repo2.getAccount(AccountId('acc-reopen'));
        expect(found, isNotNull);
        expect(found!.name, equals('Reopen Test'));
      },
    );

    test(
      'envelope persisted in session 1 is visible after re-hydrate (session 2)',
      () async {
        final repo1 = DriftCatalogRepository(db);
        await repo1.hydrate();

        await repo1.saveEnvelope(
          Envelope(
            id: EnvelopeId('env-reopen'),
            name: 'Reopen Envelope',
            role: EnvelopeRole.none,
            isArchived: false,
            updatedAt: DateTime.utc(2026, 6, 16),
          ),
        );

        final repo2 = DriftCatalogRepository(db);
        await repo2.hydrate();

        final found = repo2.getEnvelope(EnvelopeId('env-reopen'));
        expect(found, isNotNull);
        expect(found!.name, equals('Reopen Envelope'));
      },
    );
  });

  group('Full boot sequence integration', () {
    test(
      'boot: hydrate catalog + replay events reconstructs full state',
      () async {
        // === Session 1: record ===
        final store = DriftEventStore(db);
        final catalogRepo = DriftCatalogRepository(db);
        await catalogRepo.hydrate();

        await catalogRepo.saveAccount(
          Account(
            id: AccountId('acc-boot'),
            name: 'Boot Account',
            nativeCurrency: CurrencyCode('USD'),
            isArchived: false,
            updatedAt: DateTime.utc(2026, 6, 16),
          ),
        );

        await store.append(
          _buildTx(
            eventId: 'boot-evt-1',
            accountId: 'acc-boot',
            envelopeId: 'sys-stage',
            amountUsd: 10000,
            currency: 'USD',
          ),
        );
        await store.append(
          _buildTx(
            eventId: 'boot-evt-2',
            accountId: 'acc-boot',
            envelopeId: 'sys-opening',
            amountUsd: 5000,
            currency: 'USD',
          ),
        );

        // === Session 2: reopen (fresh instances, same DB) ===
        final catalogRepo2 = DriftCatalogRepository(db);
        await catalogRepo2.hydrate();

        final projections2 = await _replay(db);

        // Catalog reconstructed
        expect(catalogRepo2.getAccount(AccountId('acc-boot')), isNotNull);
        expect(
          catalogRepo2.getSystemEnvelope(EnvelopeRole.stage),
          equals(EnvelopeId('sys-stage')),
        );

        // Projections reconstructed
        expect(
          projections2.accountBalance(AccountId('acc-boot')).usd,
          equals(15000),
        );
        expect(
          projections2.envelopeUsdBalance(EnvelopeId('sys-stage')),
          equals(10000),
        );
        expect(
          projections2.envelopeUsdBalance(EnvelopeId('sys-opening')),
          equals(5000),
        );
      },
    );
  });
}
