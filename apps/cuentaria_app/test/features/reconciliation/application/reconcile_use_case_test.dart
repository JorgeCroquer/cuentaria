import 'package:contabilidad/application/catalog/exceptions.dart';
import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/ledger/factories/record_adjustment.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/reconciliation/reconciliation_planner.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:cuentaria_app/features/capture/application/rate_exceptions.dart';
import 'package:cuentaria_app/features/reconciliation/application/reconcile_use_case.dart';
import 'package:decimal/decimal.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/domain/rate_observation.dart';
import 'package:tasas/infrastructure/in_memory/in_memory_rate_series.dart';

void main() {
  group('ReconcileUseCase', () {
    late InMemoryEventStore store;
    late InMemoryLedgerProjections projections;
    late InMemoryCatalogRepository catalog;
    late InMemoryRateSeries rateSeries;
    late RecordTransaction record;
    late ReconcileUseCase useCase;

    late AccountId usdAccountId;
    late AccountId vesAccountId;
    late EnvelopeId adjustmentsId;

    setUp(() {
      store = InMemoryEventStore();
      projections = InMemoryLedgerProjections();
      catalog = InMemoryCatalogRepository();
      rateSeries = InMemoryRateSeries();

      final validator = ReferentialIntegrityValidator(catalog);
      record = RecordTransaction(
        store: store,
        projections: projections,
        eventBus: SyncEventBus(),
        validator: validator,
      );

      useCase = ReconcileUseCase(
        recordAdjustment: RecordAdjustment(
          record: record,
          projections: projections,
          catalog: catalog,
        ),
        catalog: catalog,
        projections: projections,
        rateSeries: rateSeries,
      );

      usdAccountId = AccountId('acc-usd');
      catalog.saveAccount(
        Account(
          id: usdAccountId,
          name: 'USD wallet',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      vesAccountId = AccountId('acc-ves');
      catalog.saveAccount(
        Account(
          id: vesAccountId,
          name: 'Bs wallet',
          nativeCurrency: CurrencyCode('VES'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      adjustmentsId = catalog.getSystemEnvelope(EnvelopeRole.adjustments);
    });

    test('real balance equal to projected is nothing to reconcile, posts '
        'nothing', () async {
      final outcome = await useCase(
        eventId: EventId('evt-1'),
        deviceId: 'dev-1',
        accountId: usdAccountId,
        realNativeBalance: Money(
          amount: BigInt.zero,
          currency: CurrencyCode('USD'),
        ),
      );

      expect(outcome, isA<NothingToReconcile>());
      expect(store.events, isEmpty);
    });

    test(
      'small USD surplus absorbs against the Adjustments envelope',
      () async {
        final outcome = await useCase(
          eventId: EventId('evt-2'),
          deviceId: 'dev-1',
          accountId: usdAccountId,
          realNativeBalance: Money(
            amount: BigInt.from(50),
            currency: CurrencyCode('USD'),
          ),
        );

        expect(outcome, isA<Absorb>());
        final tx = store.events.single;
        expect(tx.metadata.type, 'Adjustment');
        expect(projections.accountBalance(usdAccountId).usd, 50);
        expect(projections.envelopeUsdBalance(adjustmentsId), 50);
      },
    );

    test('foreign currency account with no observed rate throws '
        'RateNotAvailable and posts nothing', () async {
      await expectLater(
        () => useCase(
          eventId: EventId('evt-3'),
          deviceId: 'dev-1',
          accountId: vesAccountId,
          realNativeBalance: Money(
            amount: BigInt.from(100),
            currency: CurrencyCode('VES'),
          ),
        ),
        throwsA(isA<RateNotAvailable>()),
      );

      expect(store.events, isEmpty);
    });

    test('VES shortage within tolerance (at today\'s hyperinflated rate) '
        'absorbs valued at the account\'s frozen base cost — not the rate — '
        'and Σ usd[Account] == Σ usd[Envelope] still squares', () async {
      // Today's parallel rate is enormous (hyperinflation): a shortage that
      // looks negligible once converted at it can still represent a real
      // loss valued at the account's much cheaper historical cost basis.
      await rateSeries.append(
        RateObservation(
          currency: CurrencyCode('VES'),
          nativePerUsd: Decimal.parse('4000000'),
          observedAt: DateTime.now().toUtc(),
          source: 'manual:paralelo',
        ),
      );

      // Seed a known balance: 1,000,000 VES minor units costing $5,000.00
      // (average cost: 0.5 USD-cents per VES minor unit).
      final stageId = catalog.getSystemEnvelope(EnvelopeRole.stage);
      final seedMetadata = TransactionMetadata(
        eventId: EventId('evt-seed'),
        type: 'Income',
        occurredAt: DomainTimestamp(DateTime.now().toUtc()),
        recordedAt: DomainTimestamp(DateTime.now().toUtc()),
        deviceId: 'dev-1',
        schemaVersion: 1,
      );
      await record(
        postings: [
          Posting(
            target: AccountTarget(vesAccountId),
            amountNative: Money(
              amount: BigInt.from(1000000),
              currency: CurrencyCode('VES'),
            ),
            currency: CurrencyCode('VES'),
            amountUsd: 500000,
          ),
          Posting(
            target: EnvelopeTarget(stageId),
            amountNative: Money(
              amount: BigInt.from(500000),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: 500000,
          ),
        ],
        metadata: seedMetadata,
      );

      // Real balance is 996,000 VES: delta = -4,000 minor units.
      // At today's rate that's -$0.001, trivially under tolerance, so it
      // absorbs — but the frozen cost basis values it at -$20.00.
      final outcome = await useCase(
        eventId: EventId('evt-4'),
        deviceId: 'dev-1',
        accountId: vesAccountId,
        realNativeBalance: Money(
          amount: BigInt.from(996000),
          currency: CurrencyCode('VES'),
        ),
      );

      expect(outcome, isA<Absorb>());
      final tx = store.events.last;
      final pAcc = tx.postings.firstWhere((p) => p.target is AccountTarget);
      final pEnv = tx.postings.firstWhere((p) => p.target is EnvelopeTarget);
      expect(pAcc.amountUsd, -2000); // baseCostOf(4000) = -$20.00
      expect(pEnv.amountUsd, -2000);

      expect(projections.accountBalance(vesAccountId).usd, 500000 - 2000);
      expect(projections.envelopeUsdBalance(adjustmentsId), -2000);
    });

    test('large VES surplus routes to income and posts nothing unless '
        'forced', () async {
      await rateSeries.append(
        RateObservation(
          currency: CurrencyCode('VES'),
          nativePerUsd: Decimal.parse('100.00'),
          observedAt: DateTime.now().toUtc(),
          source: 'manual:paralelo',
        ),
      );

      final outcome = await useCase(
        eventId: EventId('evt-5'),
        deviceId: 'dev-1',
        accountId: vesAccountId,
        realNativeBalance: Money(
          amount: BigInt.from(20000000), // $2000.00 at 100 VES/USD
          currency: CurrencyCode('VES'),
        ),
      );

      expect(outcome, isA<RouteToIncome>());
      expect(store.events, isEmpty);
    });

    test('large VES surplus absorbs anyway when forced (escape hatch, '
        'ADR-0019 §1), valued at the parallel rate', () async {
      await rateSeries.append(
        RateObservation(
          currency: CurrencyCode('VES'),
          nativePerUsd: Decimal.parse('100.00'),
          observedAt: DateTime.now().toUtc(),
          source: 'manual:paralelo',
        ),
      );

      final outcome = await useCase(
        eventId: EventId('evt-6'),
        deviceId: 'dev-1',
        accountId: vesAccountId,
        realNativeBalance: Money(
          amount: BigInt.from(20000000),
          currency: CurrencyCode('VES'),
        ),
        forceAbsorb: true,
      );

      expect(outcome, isA<RouteToIncome>());
      final tx = store.events.single;
      final pAcc = tx.postings.firstWhere((p) => p.target is AccountTarget);
      expect(pAcc.amountUsd, 200000);
      expect(projections.accountBalance(vesAccountId).usd, 200000);
      expect(projections.envelopeUsdBalance(adjustmentsId), 200000);
    });

    test('throws TargetNotFound for an unknown account', () async {
      await expectLater(
        () => useCase(
          eventId: EventId('evt-7'),
          deviceId: 'dev-1',
          accountId: AccountId('missing'),
          realNativeBalance: Money(
            amount: BigInt.from(100),
            currency: CurrencyCode('USD'),
          ),
        ),
        throwsA(isA<TargetNotFound>()),
      );
    });
  });
}
