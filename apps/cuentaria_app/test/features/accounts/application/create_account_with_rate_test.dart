import 'package:contabilidad/application/catalog/create_account.dart';
import 'package:contabilidad/application/ledger/factories/record_opening.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:cuentaria_app/features/accounts/application/create_account_with_rate.dart';
import 'package:decimal/decimal.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/infrastructure/in_memory/in_memory_rate_series.dart';

void main() {
  group('CreateAccountWithRate', () {
    late InMemoryCatalogRepository catalog;
    late InMemoryLedgerProjections projections;
    late InMemoryRateSeries rateSeries;
    late CreateAccountWithRate createAccountWithRate;

    setUp(() {
      final store = InMemoryEventStore();
      catalog = InMemoryCatalogRepository();
      projections = InMemoryLedgerProjections();
      rateSeries = InMemoryRateSeries();

      final recordTransaction = RecordTransaction(
        store: store,
        projections: projections,
        eventBus: SyncEventBus(),
        validator: ReferentialIntegrityValidator(catalog),
      );
      final recordOpening = RecordOpening(
        record: recordTransaction,
        catalog: catalog,
        projections: projections,
      );

      createAccountWithRate = CreateAccountWithRate(
        createAccount: CreateAccount(
          catalog: catalog,
          recordOpening: recordOpening,
        ),
        rateSeries: rateSeries,
      );
    });

    test('a non-USD opening balance with a rate also registers a '
        'manual:paralelo observation, dated to the fact date', () async {
      final occurredAt = DomainTimestamp(DateTime.utc(2026, 7, 1));

      await createAccountWithRate(
        name: 'BdV',
        nativeCurrency: CurrencyCode('VES'),
        openingBalance: Money(
          amount: BigInt.from(35000),
          currency: CurrencyCode('VES'),
        ),
        openingBalanceRate: Decimal.parse('3.5'),
        eventId: EventId('evt-1'),
        deviceId: 'dev-1',
        occurredAt: occurredAt,
      );

      final observation = await rateSeries.latestFor(
        CurrencyCode('VES'),
        source: 'manual:paralelo',
      );

      expect(observation, isNotNull);
      expect(observation!.nativePerUsd, Decimal.parse('3.5'));
      expect(observation.observedAt, occurredAt.value);
    });

    test('a non-USD account without an opening balance still registers the '
        'rate the user typed, dated to now', () async {
      await createAccountWithRate(
        name: 'BdV',
        nativeCurrency: CurrencyCode('VES'),
        openingBalanceRate: Decimal.parse('90'),
        eventId: EventId('evt-2'),
        deviceId: 'dev-1',
      );

      final observation = await rateSeries.latestFor(
        CurrencyCode('VES'),
        source: 'manual:paralelo',
      );

      expect(observation, isNotNull);
      expect(observation!.nativePerUsd, Decimal.parse('90'));
    });

    test('a USD account never registers a rate observation', () async {
      await createAccountWithRate(
        name: 'Binance',
        nativeCurrency: CurrencyCode('USD'),
        eventId: EventId('evt-3'),
        deviceId: 'dev-1',
      );

      final observation = await rateSeries.latestFor(CurrencyCode('USD'));
      expect(observation, isNull);
    });

    test('no rate typed means no observation is registered', () async {
      await createAccountWithRate(
        name: 'BdV',
        nativeCurrency: CurrencyCode('VES'),
        eventId: EventId('evt-4'),
        deviceId: 'dev-1',
      );

      final observation = await rateSeries.latestFor(CurrencyCode('VES'));
      expect(observation, isNull);
    });
  });
}
