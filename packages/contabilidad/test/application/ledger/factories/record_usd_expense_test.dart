import 'package:test/test.dart';
import 'package:event_bus/event_bus.dart';
import 'package:shared_kernel/shared_kernel.dart';

import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/application/ledger/exceptions.dart';
import 'package:contabilidad/application/ledger/factories/record_usd_expense.dart';

void main() {
  group('RecordUsdExpense', () {
    late InMemoryEventStore store;
    late InMemoryLedgerProjections projections;
    late SyncEventBus eventBus;
    late InMemoryCatalogRepository catalog;
    late RecordTransaction recordTransaction;
    late RecordUsdExpense recordUsdExpense;

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

      recordUsdExpense = RecordUsdExpense(
        record: recordTransaction,
        catalog: catalog,
      );
    });

    test('expense deducts from USD account and envelope', () async {
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

      final envelopeId = EnvelopeId('env-1');
      catalog.saveEnvelope(
        Envelope(
          id: envelopeId,
          name: 'Food',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      await recordUsdExpense(
        eventId: EventId('evt-1'),
        deviceId: 'dev-1',
        accountId: accountId,
        envelopeId: envelopeId,
        amount: Money(
          amount: BigInt.from(5000),
          currency: CurrencyCode('USD'),
        ), // 50 USD
      );

      expect(store.events.length, equals(1));
      final tx = store.events.first;
      expect(tx.metadata.type, equals('Expense'));

      expect(projections.accountBalance(accountId).usd, equals(-5000));
      expect(projections.envelopeUsdBalance(envelopeId), equals(-5000));
    });

    test(
      'expense exceeding the account balance still posts, leaving a '
      'negative balance (#113 — same rule as foreign-currency accounts)',
      () async {
        final accountId = AccountId('acc-usd-sobregiro');
        catalog.saveAccount(
          Account(
            id: accountId,
            name: 'USD Account',
            nativeCurrency: CurrencyCode('USD'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        final envelopeId = EnvelopeId('env-1');
        catalog.saveEnvelope(
          Envelope(
            id: envelopeId,
            name: 'Food',
            role: EnvelopeRole.none,
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        // No opening balance was funded: any positive spend overdraws it.
        await recordUsdExpense(
          eventId: EventId('evt-sobregiro'),
          deviceId: 'dev-1',
          accountId: accountId,
          envelopeId: envelopeId,
          amount: Money(
            amount: BigInt.from(5000),
            currency: CurrencyCode('USD'),
          ),
        );

        expect(store.events.length, equals(1));
        expect(projections.accountBalance(accountId).usd, equals(-5000));
        expect(projections.envelopeUsdBalance(envelopeId), equals(-5000));
      },
    );

    test('expense rejects non-USD account', () async {
      final accountId = AccountId('acc-ves');
      catalog.saveAccount(
        Account(
          id: accountId,
          name: 'VES Account',
          nativeCurrency: CurrencyCode('VES'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      final envelopeId = EnvelopeId('env-1');
      catalog.saveEnvelope(
        Envelope(
          id: envelopeId,
          name: 'Food',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      await expectLater(
        () => recordUsdExpense(
          eventId: EventId('evt-2'),
          deviceId: 'dev-1',
          accountId: accountId,
          envelopeId: envelopeId,
          amount: Money(
            amount: BigInt.from(500),
            currency: CurrencyCode('VES'),
          ),
        ),
        throwsA(isA<UsdOnlyOperation>()),
      );

      expect(store.events.isEmpty, isTrue);
    });

    test('expense rejects negative or zero amount', () async {
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

      final envelopeId = EnvelopeId('env-1');
      catalog.saveEnvelope(
        Envelope(
          id: envelopeId,
          name: 'Food',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      await expectLater(
        () => recordUsdExpense(
          eventId: EventId('evt-3'),
          deviceId: 'dev-1',
          accountId: accountId,
          envelopeId: envelopeId,
          amount: Money(
            amount: BigInt.from(-500),
            currency: CurrencyCode('USD'),
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );

      await expectLater(
        () => recordUsdExpense(
          eventId: EventId('evt-4'),
          deviceId: 'dev-1',
          accountId: accountId,
          envelopeId: envelopeId,
          amount: Money(amount: BigInt.from(0), currency: CurrencyCode('USD')),
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(store.events.isEmpty, isTrue);
    });

    test('persists the memo when a note is provided', () async {
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

      final envelopeId = EnvelopeId('env-1');
      catalog.saveEnvelope(
        Envelope(
          id: envelopeId,
          name: 'Food',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      await recordUsdExpense(
        eventId: EventId('evt-5'),
        deviceId: 'dev-1',
        accountId: accountId,
        envelopeId: envelopeId,
        amount: Money(amount: BigInt.from(500), currency: CurrencyCode('USD')),
        memo: 'Lunch with the team',
      );

      expect(store.events.single.metadata.memo, 'Lunch with the team');
    });

    test('does not persist an empty memo', () async {
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

      final envelopeId = EnvelopeId('env-1');
      catalog.saveEnvelope(
        Envelope(
          id: envelopeId,
          name: 'Food',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      await recordUsdExpense(
        eventId: EventId('evt-6'),
        deviceId: 'dev-1',
        accountId: accountId,
        envelopeId: envelopeId,
        amount: Money(amount: BigInt.from(500), currency: CurrencyCode('USD')),
        memo: '',
      );

      expect(store.events.single.metadata.memo, isNull);
    });
  });
}
