import 'package:test/test.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/ledger/exceptions.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:event_bus/event_bus.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/application/ledger/factories/record_acquisition_conversion.dart';

void main() {
  group('RecordAcquisitionConversion', () {
    late InMemoryEventStore store;
    late InMemoryLedgerProjections projections;
    late SyncEventBus eventBus;
    late InMemoryCatalogRepository catalog;
    late RecordTransaction record;
    late RecordAcquisitionConversion factory;

    setUp(() {
      store = InMemoryEventStore();
      projections = InMemoryLedgerProjections();
      eventBus = SyncEventBus();
      catalog = InMemoryCatalogRepository();

      final validator = ReferentialIntegrityValidator(catalog);
      record = RecordTransaction(
        store: store,
        projections: projections,
        eventBus: eventBus,
        validator: validator,
      );

      factory = RecordAcquisitionConversion(record: record, catalog: catalog);
    });

    test(
      'produces 2 balanced postings inheriting USD cost and storing rateRef',
      () async {
        final usdAccountId = AccountId('acc-usd');
        final bsAccountId = AccountId('acc-bs');

        catalog.saveAccount(
          Account(
            id: usdAccountId,
            name: 'USD Cash',
            nativeCurrency: CurrencyCode('USD'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        catalog.saveAccount(
          Account(
            id: bsAccountId,
            name: 'Bs Bank',
            nativeCurrency: CurrencyCode('VES'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        await factory(
          eventId: EventId('evt-conv-1'),
          deviceId: 'dev-1',
          sourceUsdAccountId: usdAccountId,
          destinationForeignAccountId: bsAccountId,
          usdAmount: Money(
            amount: BigInt.from(10000),
            currency: CurrencyCode('USD'),
          ), // $100.00
          foreignAmountReceived: Money(
            amount: BigInt.from(400000),
            currency: CurrencyCode('VES'),
          ), // 4000.00 Bs
          rateRef: '40.00 VES/USD',
        );

        expect(store.events.length, equals(1));
        final event = store.events.first;
        expect(event.metadata.type, equals('AcquisitionConversion'));

        expect(event.postings.length, equals(2));

        final postingUsd = event.postings[0];
        expect(postingUsd.target, equals(AccountTarget(usdAccountId)));
        expect(
          postingUsd.amountNative,
          equals(
            Money(amount: BigInt.from(-10000), currency: CurrencyCode('USD')),
          ),
        );
        expect(postingUsd.amountUsd, equals(-10000));
        expect(postingUsd.rateRef, isNull);

        final postingBs = event.postings[1];
        expect(postingBs.target, equals(AccountTarget(bsAccountId)));
        expect(
          postingBs.amountNative,
          equals(
            Money(amount: BigInt.from(400000), currency: CurrencyCode('VES')),
          ),
        );
        expect(postingBs.amountUsd, equals(10000)); // inherits exact cost
        expect(postingBs.rateRef, equals('40.00 VES/USD'));
      },
    );

    test('rejects if source account is not USD', () async {
      final eurAccountId = AccountId('acc-eur');
      final bsAccountId = AccountId('acc-bs');

      catalog.saveAccount(
        Account(
          id: eurAccountId,
          name: 'EUR',
          nativeCurrency: CurrencyCode('EUR'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );
      catalog.saveAccount(
        Account(
          id: bsAccountId,
          name: 'Bs',
          nativeCurrency: CurrencyCode('VES'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      await expectLater(
        () => factory(
          eventId: EventId('evt-conv-2'),
          deviceId: 'dev-1',
          sourceUsdAccountId: eurAccountId,
          destinationForeignAccountId: bsAccountId,
          usdAmount: Money(
            amount: BigInt.from(100),
            currency: CurrencyCode('USD'),
          ),
          foreignAmountReceived: Money(
            amount: BigInt.from(4000),
            currency: CurrencyCode('VES'),
          ),
          rateRef: '40',
        ),
        throwsA(isA<UsdOnlyOperation>()),
      );
    });

    test('rejects if destination account is USD', () async {
      final usdAccountId = AccountId('acc-usd');
      final usd2AccountId = AccountId('acc-usd2');

      catalog.saveAccount(
        Account(
          id: usdAccountId,
          name: 'USD 1',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );
      catalog.saveAccount(
        Account(
          id: usd2AccountId,
          name: 'USD 2',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      await expectLater(
        () => factory(
          eventId: EventId('evt-conv-3'),
          deviceId: 'dev-1',
          sourceUsdAccountId: usdAccountId,
          destinationForeignAccountId: usd2AccountId,
          usdAmount: Money(
            amount: BigInt.from(100),
            currency: CurrencyCode('USD'),
          ),
          foreignAmountReceived: Money(
            amount: BigInt.from(100),
            currency: CurrencyCode('USD'),
          ),
          rateRef: '1',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toLowerCase(),
            'msg',
            contains('destination'),
          ),
        ),
      );
    });

    test('rejects negative or zero amounts', () async {
      final usdAccountId = AccountId('acc-usd');
      final bsAccountId = AccountId('acc-bs');

      catalog.saveAccount(
        Account(
          id: usdAccountId,
          name: 'USD',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );
      catalog.saveAccount(
        Account(
          id: bsAccountId,
          name: 'Bs',
          nativeCurrency: CurrencyCode('VES'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      // usd zero
      await expectLater(
        () => factory(
          eventId: EventId('evt-conv-4'),
          deviceId: 'dev-1',
          sourceUsdAccountId: usdAccountId,
          destinationForeignAccountId: bsAccountId,
          usdAmount: Money(
            amount: BigInt.from(0),
            currency: CurrencyCode('USD'),
          ),
          foreignAmountReceived: Money(
            amount: BigInt.from(4000),
            currency: CurrencyCode('VES'),
          ),
          rateRef: '40',
        ),
        throwsA(isA<ArgumentError>()),
      );

      // foreign zero
      await expectLater(
        () => factory(
          eventId: EventId('evt-conv-5'),
          deviceId: 'dev-1',
          sourceUsdAccountId: usdAccountId,
          destinationForeignAccountId: bsAccountId,
          usdAmount: Money(
            amount: BigInt.from(100),
            currency: CurrencyCode('USD'),
          ),
          foreignAmountReceived: Money(
            amount: BigInt.from(0),
            currency: CurrencyCode('VES'),
          ),
          rateRef: '40',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
