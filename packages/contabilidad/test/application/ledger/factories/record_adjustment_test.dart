import 'package:decimal/decimal.dart';
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

    // 6. Adjust increments foreign currency account balance valued at the
    // provided rate (ADR-0018 §1 applied to a positive Adjustment).
    test(
      'increment foreign currency account balance values the surplus with the provided rate',
      () async {
        final accountId = AccountId('acc-ves');
        final adjustmentsId = catalog.getSystemEnvelope(
          EnvelopeRole.adjustments,
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

        await recordAdjustment(
          eventId: EventId('evt-adj-2'),
          deviceId: 'dev-1',
          accountId: accountId,
          realNativeBalance: Money(
            amount: BigInt.from(2000000),
            currency: CurrencyCode('VES'),
          ), // Positive: delta = +20000.00 VES
          rate: Decimal.parse('100'), // 100.00 VES/USD
        );

        final tx = store.events.last;
        final pAcc = tx.postings.firstWhere((p) => p.target is AccountTarget);
        final pEnv = tx.postings.firstWhere((p) => p.target is EnvelopeTarget);

        expect(pAcc.amountNative.amount, equals(BigInt.from(2000000)));
        // 20000.00 VES / 100.00 VES per USD = $200.00
        expect(pAcc.amountUsd, equals(20000));

        expect(pEnv.amountNative.amount, equals(BigInt.from(20000)));
        expect(pEnv.amountUsd, equals(20000));
        expect(
          (pEnv.target as EnvelopeTarget).envelopeId,
          equals(adjustmentsId),
        );

        expect(
          projections.accountBalance(accountId).native.amount,
          equals(BigInt.from(2000000)),
        );
        expect(projections.accountBalance(accountId).usd, equals(20000));
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

    // 209. A negative adjustment that crosses the known balance (Debt
    // Account overdraft, ADR-0017 "sobregiro registrable" applied to C3)
    // values the covered part at frozen cost and the excess at the observed
    // rate — mirrors RecordTransfer's splitByBalance/RateRequiredForExcess.
    test('decrement crossing the known balance splits: covered at frozen cost, '
        'excess at the provided rate', () async {
      final accountId = AccountId('acc-ves-cross');

      catalog.saveAccount(
        Account(
          id: accountId,
          name: 'Claudia',
          nativeCurrency: CurrencyCode('VES'),
          isArchived: false,
          updatedAt: DateTime.now(),
          meta: {'counterpartyName': 'Claudia'},
        ),
      );

      // Opening: 1000 VES with a frozen cost of $50.00 (5000 cents).
      final metadataOrig = TransactionMetadata(
        eventId: EventId('evt-cross-orig'),
        type: 'Income',
        occurredAt: DomainTimestamp(DateTime.now().toUtc()),
        recordedAt: DomainTimestamp(DateTime.now().toUtc()),
        deviceId: 'dev-1',
        schemaVersion: 1,
      );
      await recordTransaction(
        postings: [
          Posting(
            target: AccountTarget(accountId),
            amountNative: Money(
              amount: BigInt.from(1000),
              currency: CurrencyCode('VES'),
            ),
            currency: CurrencyCode('VES'),
            amountUsd: 5000,
          ),
          Posting(
            target: EnvelopeTarget(
              catalog.getSystemEnvelope(EnvelopeRole.stage),
            ),
            amountNative: Money(
              amount: BigInt.from(5000),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: 5000,
          ),
        ],
        metadata: metadataOrig,
      );

      // Declared real balance: -500 VES (crosses zero). Delta = -1500 VES:
      // 1000 covered at frozen cost ($50.00) + 500 excess at 100 VES/USD.
      await expectLater(
        () => recordAdjustment(
          eventId: EventId('evt-cross-1'),
          deviceId: 'dev-1',
          accountId: accountId,
          realNativeBalance: Money(
            amount: BigInt.from(-500),
            currency: CurrencyCode('VES'),
          ),
        ),
        throwsA(isA<RateRequiredForExcess>()),
      );

      await recordAdjustment(
        eventId: EventId('evt-cross-1'),
        deviceId: 'dev-1',
        accountId: accountId,
        realNativeBalance: Money(
          amount: BigInt.from(-500),
          currency: CurrencyCode('VES'),
        ),
        rate: Decimal.parse('100'),
      );

      final tx = store.events.last;
      final pAcc = tx.postings.firstWhere((p) => p.target is AccountTarget);
      final pEnv = tx.postings.firstWhere((p) => p.target is EnvelopeTarget);

      expect(pAcc.amountNative.amount, equals(BigInt.from(-1500)));
      // 5000 (covered, frozen cost) + 500 (excess) / 100 = 5 -> 5005.
      expect(pAcc.amountUsd, equals(-5005));
      expect(pEnv.amountUsd, equals(-5005));

      expect(
        projections.accountBalance(accountId).native.amount,
        equals(BigInt.from(-500)),
      );
      expect(projections.accountBalance(accountId).usd, equals(-5));
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
