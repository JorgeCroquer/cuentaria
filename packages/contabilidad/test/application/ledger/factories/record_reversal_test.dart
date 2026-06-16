import 'package:test/test.dart';
import 'package:event_bus/event_bus.dart';
import 'package:shared_kernel/shared_kernel.dart';

import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/application/ledger/exceptions.dart';
import 'package:contabilidad/application/ledger/factories/record_reversal.dart';

void main() {
  group('RecordReversal', () {
    late InMemoryEventStore store;
    late InMemoryLedgerProjections projections;
    late SyncEventBus eventBus;
    late InMemoryCatalogRepository catalog;
    late RecordTransaction recordTransaction;
    late RecordReversal recordReversal;

    setUp(() {
      store = InMemoryEventStore();
      projections = InMemoryLedgerProjections();
      eventBus = SyncEventBus();
      catalog = InMemoryCatalogRepository();

      final validator = ReferentialIntegrityValidator(catalog);
      recordTransaction = RecordTransaction(
        store: store,
        projections: projections,
        eventBus: eventBus,
        validator: validator,
      );

      recordReversal = RecordReversal(record: recordTransaction, store: store);
    });

    test(
      'reversing a simple transaction inverts the postings exactly',
      () async {
        // 1. Prepare an original transaction
        final accountId = AccountId('acc-1');
        final envelopeId = EnvelopeId('env-1');

        catalog.saveAccount(
          Account(
            id: accountId,
            name: 'USD Account',
            nativeCurrency: CurrencyCode('USD'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );
        catalog.saveEnvelope(
          Envelope(
            id: envelopeId,
            name: 'Stage',
            role: EnvelopeRole.stage,
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        final originalId = EventId('evt-orig');
        final metadataOrig = TransactionMetadata(
          eventId: originalId,
          type: 'Income',
          occurredAt: DomainTimestamp(DateTime.utc(2026, 6, 11)),
          recordedAt: DomainTimestamp(DateTime.utc(2026, 6, 11, 12)),
          deviceId: 'dev-1',
          schemaVersion: 1,
        );

        final postingsOrig = [
          Posting(
            target: AccountTarget(accountId),
            amountNative: Money(
              amount: BigInt.from(10000),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: 10000,
          ),
          Posting(
            target: EnvelopeTarget(envelopeId),
            amountNative: Money(
              amount: BigInt.from(10000),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: 10000,
          ),
        ];

        await recordTransaction(postings: postingsOrig, metadata: metadataOrig);

        expect(projections.accountBalance(accountId).usd, equals(10000));
        expect(projections.envelopeUsdBalance(envelopeId), equals(10000));

        // 2. Reverse
        await recordReversal(
          eventId: EventId('evt-rev'),
          deviceId: 'dev-2',
          originalEventId: originalId,
        );

        // 3. Verify results
        expect(store.events.length, equals(2));
        final revTx = store.events.last;

        expect(revTx.metadata.type, equals('Reversal'));
        expect(revTx.metadata.reverses, equals(originalId));
        expect(revTx.postings.length, equals(2));

        // Negation is exact
        final pAcc = revTx.postings.firstWhere(
          (p) => p.target is AccountTarget,
        );
        final pEnv = revTx.postings.firstWhere(
          (p) => p.target is EnvelopeTarget,
        );

        expect(pAcc.amountNative.amount, equals(BigInt.from(-10000)));
        expect(pAcc.amountUsd, equals(-10000));
        expect(pEnv.amountNative.amount, equals(BigInt.from(-10000)));
        expect(pEnv.amountUsd, equals(-10000));

        // Balance returns to 0
        expect(projections.accountBalance(accountId).usd, equals(0));
        expect(projections.envelopeUsdBalance(envelopeId), equals(0));
      },
    );

    test(
      'reversing a realization reverts its differential (3 postings)',
      () async {
        final accountId = AccountId('acc-bs');
        final expenseEnvelopeId = EnvelopeId('env-expense');
        final differentialId = catalog.getSystemEnvelope(
          EnvelopeRole.differential,
        );

        catalog.saveAccount(
          Account(
            id: accountId,
            name: 'Bs Account',
            nativeCurrency: CurrencyCode('VES'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );
        catalog.saveEnvelope(
          Envelope(
            id: expenseEnvelopeId,
            name: 'Food',
            role: EnvelopeRole.none,
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        final originalId = EventId('evt-realization');
        final metadataOrig = TransactionMetadata(
          eventId: originalId,
          type: 'Expense',
          occurredAt: DomainTimestamp(DateTime.utc(2026, 6, 11)),
          recordedAt: DomainTimestamp(DateTime.utc(2026, 6, 11, 12)),
          deviceId: 'dev-1',
          schemaVersion: 1,
        );

        final postingsOrig = [
          Posting(
            target: AccountTarget(accountId),
            amountNative: Money(
              amount: BigInt.from(-100000),
              currency: CurrencyCode('VES'),
            ),
            currency: CurrencyCode('VES'),
            amountUsd: -2500, // Base cost: $25.00
            rateRef: '40.0',
          ),
          Posting(
            target: EnvelopeTarget(expenseEnvelopeId),
            amountNative: Money(
              amount: BigInt.from(-2000),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: -2000, // Market value: $20.00
            rateRef: '50.0',
          ),
          Posting(
            target: EnvelopeTarget(differentialId),
            amountNative: Money(
              amount: BigInt.from(-500),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: -500, // Differential (loss): -$5.00
          ),
        ];

        await recordTransaction(postings: postingsOrig, metadata: metadataOrig);

        expect(projections.accountBalance(accountId).usd, equals(-2500));
        expect(
          projections.envelopeUsdBalance(expenseEnvelopeId),
          equals(-2000),
        );
        expect(projections.envelopeUsdBalance(differentialId), equals(-500));

        await recordReversal(
          eventId: EventId('evt-rev-2'),
          deviceId: 'dev-2',
          originalEventId: originalId,
        );

        expect(projections.accountBalance(accountId).usd, equals(0));
        expect(projections.envelopeUsdBalance(expenseEnvelopeId), equals(0));
        expect(projections.envelopeUsdBalance(differentialId), equals(0));
      },
    );

    test('throws TransactionNotFound if original does not exist', () async {
      await expectLater(
        () => recordReversal(
          eventId: EventId('evt-rev-3'),
          deviceId: 'dev-1',
          originalEventId: EventId('non-existent'),
        ),
        throwsA(isA<TransactionNotFound>()),
      );
    });

    test('throws TransactionAlreadyReversed if already reversed', () async {
      final accountId = AccountId('acc-1');
      catalog.saveAccount(
        Account(
          id: accountId,
          name: 'USD Account',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      final originalId = EventId('evt-orig-2');
      final metadataOrig = TransactionMetadata(
        eventId: originalId,
        type: 'Income',
        occurredAt: DomainTimestamp(DateTime.utc(2026, 6, 11)),
        recordedAt: DomainTimestamp(DateTime.utc(2026, 6, 11, 12)),
        deviceId: 'dev-1',
        schemaVersion: 1,
      );

      final postingsOrig = [
        Posting(
          target: AccountTarget(accountId),
          amountNative: Money(
            amount: BigInt.from(100),
            currency: CurrencyCode('USD'),
          ),
          currency: CurrencyCode('USD'),
          amountUsd: 100,
        ),
        Posting(
          target: EnvelopeTarget(catalog.getSystemEnvelope(EnvelopeRole.stage)),
          amountNative: Money(
            amount: BigInt.from(100),
            currency: CurrencyCode('USD'),
          ),
          currency: CurrencyCode('USD'),
          amountUsd: 100,
        ),
      ];

      await recordTransaction(postings: postingsOrig, metadata: metadataOrig);

      // First reversal
      await recordReversal(
        eventId: EventId('evt-rev-4'),
        deviceId: 'dev-2',
        originalEventId: originalId,
      );

      // Attempt double reversal
      await expectLater(
        () => recordReversal(
          eventId: EventId('evt-rev-5'),
          deviceId: 'dev-2',
          originalEventId: originalId,
        ),
        throwsA(isA<TransactionAlreadyReversed>()),
      );
    });
  });
}
