import 'package:test/test.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:contabilidad/application/ledger/rebuild_projections.dart';

void main() {
  group('RebuildProjections', () {
    test('clears and rebuilds identical state from the event log', () async {
      final store = InMemoryEventStore();
      final projections = InMemoryLedgerProjections();

      Transaction createTx(String id, int amount) {
        return Transaction.create(
          metadata: TransactionMetadata(
            eventId: EventId(id),
            type: 'Test',
            occurredAt: DomainTimestamp(DateTime.utc(2026, 6, 1)),
            recordedAt: DomainTimestamp(DateTime.utc(2026, 6, 1)),
            deviceId: 'dev',
            schemaVersion: 1,
          ),
          postings: [
            Posting(
              target: AccountTarget(AccountId('acc-1')),
              amountNative: Money(
                amount: BigInt.from(amount),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: amount,
            ),
            Posting(
              target: EnvelopeTarget(EnvelopeId('env-1')),
              amountNative: Money(
                amount: BigInt.from(amount),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: amount,
            ),
          ],
        );
      }

      final tx1 = createTx('evt-1', 100);
      final tx2 = createTx('evt-2', 200);

      // Simulate initial incremental recording
      await store.append(tx1);
      projections.apply(tx1);

      await store.append(tx2);
      projections.apply(tx2);

      final originalAccountBalance = projections.accountBalance(
        AccountId('acc-1'),
      );
      final originalEnvelopeBalance = projections.envelopeUsdBalance(
        EnvelopeId('env-1'),
      );

      expect(originalAccountBalance.usd, equals(300));
      expect(originalEnvelopeBalance, equals(300));

      // Clear (discard state)
      projections.clear();
      expect(projections.accountBalance(AccountId('acc-1')).usd, equals(0));
      expect(projections.envelopeUsdBalance(EnvelopeId('env-1')), equals(0));

      // Run use case
      final reconstructor = RebuildProjections(
        store: store,
        projections: projections,
      );

      await reconstructor.execute();

      // Verify exact reconstruction
      final rebuiltAccountBalance = projections.accountBalance(
        AccountId('acc-1'),
      );
      final rebuiltEnvelopeBalance = projections.envelopeUsdBalance(
        EnvelopeId('env-1'),
      );

      expect(
        rebuiltAccountBalance.native.amount,
        equals(originalAccountBalance.native.amount),
      );
      expect(rebuiltAccountBalance.usd, equals(originalAccountBalance.usd));
      expect(rebuiltEnvelopeBalance, equals(originalEnvelopeBalance));
    });

    test(
      'Property Test: auto-heal and identical state after replay with backdated events',
      () async {
        final store = InMemoryEventStore();
        final incrementalProjections = InMemoryLedgerProjections();
        final replayProjections = InMemoryLedgerProjections();

        Transaction createTx(String id, int amount, DateTime occurred) {
          return Transaction.create(
            metadata: TransactionMetadata(
              eventId: EventId(id),
              type: 'Test',
              occurredAt: DomainTimestamp(occurred),
              recordedAt: DomainTimestamp(
                DateTime.now().toUtc(),
              ), // Inserted now
              deviceId: 'dev',
              schemaVersion: 1,
            ),
            postings: [
              Posting(
                target: AccountTarget(AccountId('acc-property')),
                amountNative: Money(
                  amount: BigInt.from(amount),
                  currency: CurrencyCode('USD'),
                ),
                currency: CurrencyCode('USD'),
                amountUsd: amount,
              ),
              Posting(
                target: EnvelopeTarget(EnvelopeId('env-property')),
                amountNative: Money(
                  amount: BigInt.from(amount),
                  currency: CurrencyCode('USD'),
                ),
                currency: CurrencyCode('USD'),
                amountUsd: amount,
              ),
            ],
          );
        }

        // Event 1 occurs on day 2
        final tx1 = createTx('evt-day-2', 100, DateTime.utc(2026, 6, 2));
        // Event 2 occurs on day 3
        final tx2 = createTx('evt-day-3', 200, DateTime.utc(2026, 6, 3));
        // Event 3 OCCURS ON DAY 1 (BACKDATED), but recorded last
        final tx3 = createTx('evt-day-1', 50, DateTime.utc(2026, 6, 1));

        // Insertion/arrival order (incrementalProjections applies in this order)
        await store.append(tx1);
        incrementalProjections.apply(tx1);

        await store.append(tx2);
        incrementalProjections.apply(tx2);

        await store.append(tx3);
        incrementalProjections.apply(tx3);

        final accountId = AccountId('acc-property');
        final envelopeId = EnvelopeId('env-property');

        final incAccount = incrementalProjections.accountBalance(accountId);
        final incEnvelope = incrementalProjections.envelopeUsdBalance(
          envelopeId,
        );

        // Total is sum of frozen amounts (commutative) => 100+200+50 = 350
        expect(incAccount.usd, equals(350));
        expect(incEnvelope, equals(350));

        // Replay
        final reconstructor = RebuildProjections(
          store: store,
          projections: replayProjections,
        );
        await reconstructor.execute();

        final repAccount = replayProjections.accountBalance(accountId);
        final repEnvelope = replayProjections.envelopeUsdBalance(envelopeId);

        // Verify that despite different application order, state is identical
        expect(repAccount.native.amount, equals(incAccount.native.amount));
        expect(repAccount.usd, equals(incAccount.usd));
        expect(repEnvelope, equals(incEnvelope));
      },
    );
  });
}
