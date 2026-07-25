import 'package:decimal/decimal.dart';
import 'package:test/test.dart';
import 'package:event_bus/event_bus.dart';
import 'package:shared_kernel/shared_kernel.dart';

import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/ledger/exceptions.dart';
import 'package:contabilidad/application/ledger/factories/record_acquisition_conversion.dart';
import 'package:contabilidad/application/ledger/factories/record_transfer.dart';
import 'package:contabilidad/application/ledger/quick_add_mover_use_case.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';

void main() {
  group('QuickAddMoverUseCase', () {
    late InMemoryEventStore store;
    late InMemoryLedgerProjections projections;
    late InMemoryCatalogRepository catalog;
    late QuickAddMoverUseCase useCase;

    AccountId usdAccountId(String id) => AccountId(id);

    void addAccount(String id, String currency) {
      catalog.saveAccount(
        Account(
          id: AccountId(id),
          name: id,
          nativeCurrency: CurrencyCode(currency),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );
    }

    setUp(() {
      store = InMemoryEventStore();
      projections = InMemoryLedgerProjections();
      catalog = InMemoryCatalogRepository();
      final eventBus = SyncEventBus();
      final validator = ReferentialIntegrityValidator(catalog);
      final record = RecordTransaction(
        store: store,
        projections: projections,
        eventBus: eventBus,
        validator: validator,
      );

      useCase = QuickAddMoverUseCase(
        recordTransfer: RecordTransfer(record: record, catalog: catalog),
        recordAcquisitionConversion: RecordAcquisitionConversion(
          record: record,
          catalog: catalog,
        ),
        catalog: catalog,
      );
    });

    test('same currency dispatches a Transfer', () async {
      addAccount('facebank', 'USD');
      addAccount('zinli', 'USD');

      await useCase(
        eventId: EventId('evt-1'),
        deviceId: 'dev-1',
        sourceAccountId: usdAccountId('facebank'),
        destinationAccountId: usdAccountId('zinli'),
        givenAmount: Money(
          amount: BigInt.from(5000),
          currency: CurrencyCode('USD'),
        ),
      );

      final log = await store.queryLog();
      expect(log.single.metadata.type, 'Transfer');
      expect(projections.accountBalance(AccountId('facebank')).usd, -5000);
      expect(projections.accountBalance(AccountId('zinli')).usd, 5000);
    });

    test(
      'different currency with an explicit received amount dispatches an '
      'AcquisitionConversion carrying a rateRef, not a stored rate field',
      () async {
        addAccount('binance', 'USD');
        addAccount('bdv', 'VES');

        await useCase(
          eventId: EventId('evt-2'),
          deviceId: 'dev-1',
          sourceAccountId: usdAccountId('binance'),
          destinationAccountId: usdAccountId('bdv'),
          givenAmount: Money(
            amount: BigInt.from(10000),
            currency: CurrencyCode('USD'),
          ), // $100.00
          receivedAmount: Money(
            amount: BigInt.from(400000),
            currency: CurrencyCode('VES'),
          ), // 4000.00 Bs
        );

        final log = await store.queryLog();
        final tx = log.single;
        expect(tx.metadata.type, 'AcquisitionConversion');
        expect(tx.postings.length, 2);
        final bsPosting = tx.postings.last;
        expect(bsPosting.amountUsd, 10000);
        expect(bsPosting.rateRef, '40.00 VES/USD');
        expect(
          projections.accountBalance(AccountId('bdv')).native.amount,
          BigInt.from(400000),
        );
      },
    );

    test('different currency with only a rate derives the received amount '
        '(single rounding, native-per-USD)', () async {
      addAccount('binance', 'USD');
      addAccount('bdv', 'VES');

      await useCase(
        eventId: EventId('evt-3'),
        deviceId: 'dev-1',
        sourceAccountId: usdAccountId('binance'),
        destinationAccountId: usdAccountId('bdv'),
        givenAmount: Money(
          amount: BigInt.from(250),
          currency: CurrencyCode('USD'),
        ), // $2.50
        rate: Decimal.parse('20'),
      );

      final log = await store.queryLog();
      final tx = log.single;
      expect(tx.metadata.type, 'AcquisitionConversion');
      expect(
        projections.accountBalance(AccountId('bdv')).native.amount,
        BigInt.from(5000), // 50.00 Bs
      );
    });

    test(
      'different currency without a received amount or rate throws',
      () async {
        addAccount('binance', 'USD');
        addAccount('bdv', 'VES');

        await expectLater(
          () => useCase(
            eventId: EventId('evt-4'),
            deviceId: 'dev-1',
            sourceAccountId: usdAccountId('binance'),
            destinationAccountId: usdAccountId('bdv'),
            givenAmount: Money(
              amount: BigInt.from(100),
              currency: CurrencyCode('USD'),
            ),
          ),
          throwsArgumentError,
        );
      },
    );

    test(
      'reuses RecordAcquisitionConversion validation for a non-USD source',
      () async {
        addAccount('binance-eur', 'EUR');
        addAccount('bdv', 'VES');

        await expectLater(
          () => useCase(
            eventId: EventId('evt-5'),
            deviceId: 'dev-1',
            sourceAccountId: usdAccountId('binance-eur'),
            destinationAccountId: usdAccountId('bdv'),
            givenAmount: Money(
              amount: BigInt.from(100),
              currency: CurrencyCode('EUR'),
            ),
            rate: Decimal.parse('40'),
          ),
          throwsA(isA<UsdOnlyOperation>()),
        );
      },
    );
  });
}
