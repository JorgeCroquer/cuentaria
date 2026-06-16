import 'package:test/test.dart';
import 'package:event_bus/event_bus.dart';
import 'package:shared_kernel/shared_kernel.dart';

import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/application/ledger/exceptions.dart';
import 'package:contabilidad/application/ledger/factories/record_transfer.dart';

void main() {
  group('RecordTransfer', () {
    late InMemoryEventStore store;
    late InMemoryLedgerProjections projections;
    late SyncEventBus eventBus;
    late InMemoryCatalogRepository catalog;
    late RecordTransaction recordTransaction;
    late RecordTransfer recordTransfer;

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

      recordTransfer = RecordTransfer(
        record: recordTransaction,
        catalog: catalog,
      );
    });

    test('transfers between two USD accounts successfully', () async {
      final sourceId = AccountId('acc-usd-1');
      final destinationId = AccountId('acc-usd-2');

      catalog.saveAccount(
        Account(
          id: sourceId,
          name: 'USD Account 1',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      catalog.saveAccount(
        Account(
          id: destinationId,
          name: 'USD Account 2',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      await recordTransfer(
        eventId: EventId('evt-1'),
        deviceId: 'dev-1',
        sourceAccountId: sourceId,
        destinationAccountId: destinationId,
        amount: Money(
          amount: BigInt.from(3000),
          currency: CurrencyCode('USD'),
        ), // 30 USD
      );

      expect(store.events.length, equals(1));
      final tx = store.events.first;
      expect(tx.metadata.type, equals('Transfer'));

      expect(projections.accountBalance(sourceId).usd, equals(-3000));
      expect(projections.accountBalance(destinationId).usd, equals(3000));
    });

    test('rejects USD to EUR transfer', () async {
      final sourceId = AccountId('acc-usd-1');
      final destinationId = AccountId('acc-eur-1');

      catalog.saveAccount(
        Account(
          id: sourceId,
          name: 'USD Account',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      catalog.saveAccount(
        Account(
          id: destinationId,
          name: 'EUR Account',
          nativeCurrency: CurrencyCode('EUR'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      await expectLater(
        () => recordTransfer(
          eventId: EventId('evt-2'),
          deviceId: 'dev-1',
          sourceAccountId: sourceId,
          destinationAccountId: destinationId,
          amount: Money(
            amount: BigInt.from(3000),
            currency: CurrencyCode('USD'),
          ),
        ),
        throwsA(isA<CrossCurrencyTransfer>()),
      );

      expect(store.events.isEmpty, isTrue);
    });

    test('rejects VES to VES (must be USD only)', () async {
      final sourceId = AccountId('acc-ves-1');
      final destinationId = AccountId('acc-ves-2');

      catalog.saveAccount(
        Account(
          id: sourceId,
          name: 'VES Account 1',
          nativeCurrency: CurrencyCode('VES'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      catalog.saveAccount(
        Account(
          id: destinationId,
          name: 'VES Account 2',
          nativeCurrency: CurrencyCode('VES'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      await expectLater(
        () => recordTransfer(
          eventId: EventId('evt-3'),
          deviceId: 'dev-1',
          sourceAccountId: sourceId,
          destinationAccountId: destinationId,
          amount: Money(
            amount: BigInt.from(3000),
            currency: CurrencyCode('VES'),
          ),
        ),
        throwsA(isA<UsdOnlyOperation>()),
      );

      expect(store.events.isEmpty, isTrue);
    });

    test('transfer rejects negative or zero amount', () async {
      final sourceId = AccountId('acc-usd-1');
      final destinationId = AccountId('acc-usd-2');

      catalog.saveAccount(
        Account(
          id: sourceId,
          name: 'USD Account 1',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      catalog.saveAccount(
        Account(
          id: destinationId,
          name: 'USD Account 2',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      await expectLater(
        () => recordTransfer(
          eventId: EventId('evt-4'),
          deviceId: 'dev-1',
          sourceAccountId: sourceId,
          destinationAccountId: destinationId,
          amount: Money(
            amount: BigInt.from(-3000),
            currency: CurrencyCode('USD'),
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );

      await expectLater(
        () => recordTransfer(
          eventId: EventId('evt-5'),
          deviceId: 'dev-1',
          sourceAccountId: sourceId,
          destinationAccountId: destinationId,
          amount: Money(amount: BigInt.from(0), currency: CurrencyCode('USD')),
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(store.events.isEmpty, isTrue);
    });
  });
}
