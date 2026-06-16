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
import 'package:contabilidad/application/ledger/factories/record_adjustment.dart';

void main() {
  group('RecordAdjustment', () {
    late InMemoryEventStore store;
    late InMemoryLedgerProjections projections;
    late SyncEventBus eventBus;
    late InMemoryCatalogRepository catalog;
    late RecordTransaction recordTransaction;
    late RecordAdjustment recordAdjustment;

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

      recordAdjustment = RecordAdjustment(
        record: recordTransaction,
        projections: projections,
        catalog: catalog,
      );
    });

    // 5. Adjust increments USD account balance
    test(
      'increment USD account balance posts with positive sign in Account and Adjustments',
      () async {
        final accountId = AccountId('acc-usd');
        final adjustmentsId = catalog.getSystemEnvelope(
          EnvelopeRole.adjustments,
        );

        catalog.saveAccount(
          Account(
            id: accountId,
            name: 'USD Account',
            nativeCurrency: CurrencyCode('USD'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        // Initial balance 0
        expect(projections.accountBalance(accountId).usd, equals(0));

        await recordAdjustment(
          eventId: EventId('evt-adj-1'),
          deviceId: 'dev-1',
          accountId: accountId,
          realNativeBalance: Money(
            amount: BigInt.from(5000),
            currency: CurrencyCode('USD'),
          ), // +$50.00
        );

        expect(store.events.length, equals(1));
        final tx = store.events.first;
        expect(tx.metadata.type, equals('Adjustment'));

        final pAcc = tx.postings.firstWhere((p) => p.target is AccountTarget);
        final pEnv = tx.postings.firstWhere((p) => p.target is EnvelopeTarget);

        expect(pAcc.amountNative.amount, equals(BigInt.from(5000)));
        expect(pAcc.amountUsd, equals(5000));
        expect(pEnv.amountNative.amount, equals(BigInt.from(5000)));
        expect(pEnv.amountUsd, equals(5000));
        expect(
          (pEnv.target as EnvelopeTarget).envelopeId,
          equals(adjustmentsId),
        );

        expect(projections.accountBalance(accountId).usd, equals(5000));
        expect(projections.envelopeUsdBalance(adjustmentsId), equals(5000));
      },
    );

    // 6. Adjust rejects positive increment on foreign account
    test(
      'throws ForeignCurrencyPositiveAdjustmentNotAllowed if delta is positive on non-USD account',
      () async {
        final accountId = AccountId('acc-ves');
        catalog.saveAccount(
          Account(
            id: accountId,
            name: 'Bs Account',
            nativeCurrency: CurrencyCode('VES'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        await expectLater(
          () => recordAdjustment(
            eventId: EventId('evt-adj-2'),
            deviceId: 'dev-1',
            accountId: accountId,
            realNativeBalance: Money(
              amount: BigInt.from(100),
              currency: CurrencyCode('VES'),
            ), // Positive
          ),
          throwsA(isA<ForeignCurrencyPositiveAdjustmentNotAllowed>()),
        );
      },
    );

    // 7. Adjust decrements balance
    test('decrement balance uses base cost and negative signs', () async {
      final accountId = AccountId('acc-ves');

      catalog.saveAccount(
        Account(
          id: accountId,
          name: 'Bs Account',
          nativeCurrency: CurrencyCode('VES'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      // Inject balance manually via recordTransaction (equivalent to Income/Conversion)
      final metadataOrig = TransactionMetadata(
        eventId: EventId('evt-orig'),
        type: 'Income',
        occurredAt: DomainTimestamp(DateTime.now().toUtc()),
        recordedAt: DomainTimestamp(DateTime.now().toUtc()),
        deviceId: 'dev-1',
        schemaVersion: 1,
      );

      final postingsOrig = [
        Posting(
          target: AccountTarget(accountId),
          amountNative: Money(
            amount: BigInt.from(1000),
            currency: CurrencyCode('VES'),
          ),
          currency: CurrencyCode('VES'),
          amountUsd: 5000, // Base cost: $50.00
        ),
        Posting(
          target: EnvelopeTarget(catalog.getSystemEnvelope(EnvelopeRole.stage)),
          amountNative: Money(
            amount: BigInt.from(5000),
            currency: CurrencyCode('USD'),
          ),
          currency: CurrencyCode('USD'),
          amountUsd: 5000,
        ),
      ];

      await recordTransaction(postings: postingsOrig, metadata: metadataOrig);

      expect(
        projections.accountBalance(accountId).native.amount,
        equals(BigInt.from(1000)),
      );
      expect(projections.accountBalance(accountId).usd, equals(5000));

      // Adjustment: real balance is 800 VES. Delta = -200 VES.
      await recordAdjustment(
        eventId: EventId('evt-adj-3'),
        deviceId: 'dev-1',
        accountId: accountId,
        realNativeBalance: Money(
          amount: BigInt.from(800),
          currency: CurrencyCode('VES'),
        ),
      );

      final tx = store.events.last;

      final pAcc = tx.postings.firstWhere((p) => p.target is AccountTarget);
      final pEnv = tx.postings.firstWhere((p) => p.target is EnvelopeTarget);

      expect(pAcc.amountNative.amount, equals(BigInt.from(-200)));
      // Average base cost: 5000 USD / 1000 VES = 5.
      // -200 VES * 5 = -1000 USD.
      expect(pAcc.amountUsd, equals(-1000));

      expect(pEnv.amountNative.amount, equals(BigInt.from(-1000)));
      expect(pEnv.amountUsd, equals(-1000));

      expect(
        projections.accountBalance(accountId).native.amount,
        equals(BigInt.from(800)),
      );
      expect(projections.accountBalance(accountId).usd, equals(4000));
    });

    // 8. Adjust rejects if no difference
    test('throws AdjustmentWithNoDifference if delta is 0', () async {
      final accountId = AccountId('acc-usd');
      catalog.saveAccount(
        Account(
          id: accountId,
          name: 'USD Account',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      await expectLater(
        () => recordAdjustment(
          eventId: EventId('evt-adj-4'),
          deviceId: 'dev-1',
          accountId: accountId,
          realNativeBalance: Money(
            amount: BigInt.zero,
            currency: CurrencyCode('USD'),
          ),
        ),
        throwsA(isA<AdjustmentWithNoDifference>()),
      );
    });
  });
}
