import 'package:contabilidad/application/catalog/exceptions.dart';
import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/ledger/factories/record_income.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:cuentaria_app/features/capture/application/quick_add_income_use_case.dart';
import 'package:cuentaria_app/features/capture/application/rate_exceptions.dart';
import 'package:decimal/decimal.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/domain/rate_observation.dart';
import 'package:tasas/infrastructure/in_memory/in_memory_rate_series.dart';

void main() {
  group('QuickAddIncomeUseCase', () {
    late InMemoryEventStore store;
    late InMemoryLedgerProjections projections;
    late InMemoryCatalogRepository catalog;
    late InMemoryRateSeries rateSeries;
    late QuickAddIncomeUseCase useCase;

    late AccountId usdAccountId;
    late AccountId vesAccountId;
    late EnvelopeId stageId;

    setUp(() {
      store = InMemoryEventStore();
      projections = InMemoryLedgerProjections();
      catalog = InMemoryCatalogRepository();
      rateSeries = InMemoryRateSeries();

      final validator = ReferentialIntegrityValidator(catalog);
      final record = RecordTransaction(
        store: store,
        projections: projections,
        eventBus: SyncEventBus(),
        validator: validator,
      );

      useCase = QuickAddIncomeUseCase(
        recordIncome: RecordIncome(record: record, catalog: catalog),
        catalog: catalog,
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

      stageId = catalog.getSystemEnvelope(EnvelopeRole.stage);
    });

    test(
      'a USD destination posts the income as-is, no rate involved',
      () async {
        await useCase(
          eventId: EventId('evt-1'),
          deviceId: 'dev-1',
          accountId: usdAccountId,
          amount: Money(
            amount: BigInt.from(50000),
            currency: CurrencyCode('USD'),
          ),
          source: 'Cliente X',
        );

        final tx = store.events.single;
        expect(tx.metadata.type, 'Income');
        expect(tx.metadata.source, 'Cliente X');
        expect(projections.accountBalance(usdAccountId).usd, 50000);
        expect(projections.envelopeUsdBalance(stageId), 50000);
      },
    );

    test('a foreign currency destination values the income with the latest '
        'parallel rate observation and stages the USD equivalent', () async {
      await rateSeries.append(
        RateObservation(
          currency: CurrencyCode('VES'),
          nativePerUsd: Decimal.parse('100.00'),
          observedAt: DateTime.now().toUtc(),
          source: 'manual:paralelo',
        ),
      );
      await rateSeries.append(
        RateObservation(
          currency: CurrencyCode('VES'),
          nativePerUsd: Decimal.parse('999.00'),
          observedAt: DateTime.now().toUtc(),
          source: 'manual:bcv',
        ),
      );

      await useCase(
        eventId: EventId('evt-2'),
        deviceId: 'dev-1',
        accountId: vesAccountId,
        amount: Money(
          amount: BigInt.from(2000000),
          currency: CurrencyCode('VES'),
        ), // 20000.00 Bs
        source: 'Cliente Bs',
      );

      final tx = store.events.single;
      expect(tx.metadata.type, 'Income');
      expect(tx.metadata.source, 'Cliente Bs');

      // 20000.00 / 100.00 = $200.00 — the parallel rate, never the BCV one.
      expect(
        projections.accountBalance(vesAccountId).native.amount,
        BigInt.from(2000000),
      );
      expect(projections.accountBalance(vesAccountId).usd, 20000);
      expect(projections.envelopeUsdBalance(stageId), 20000);
    });

    test('a foreign currency destination with no observed rate throws '
        'RateNotAvailable and posts nothing', () async {
      await expectLater(
        () => useCase(
          eventId: EventId('evt-3'),
          deviceId: 'dev-1',
          accountId: vesAccountId,
          amount: Money(
            amount: BigInt.from(100),
            currency: CurrencyCode('VES'),
          ),
          source: 'Cliente Bs',
        ),
        throwsA(isA<RateNotAvailable>()),
      );

      expect(store.events, isEmpty);
    });

    test('throws TargetNotFound for an unknown account', () async {
      await expectLater(
        () => useCase(
          eventId: EventId('evt-4'),
          deviceId: 'dev-1',
          accountId: AccountId('missing'),
          amount: Money(
            amount: BigInt.from(100),
            currency: CurrencyCode('USD'),
          ),
          source: 'Cliente X',
        ),
        throwsA(isA<TargetNotFound>()),
      );
    });
  });
}
