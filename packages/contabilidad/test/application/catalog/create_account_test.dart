import 'package:contabilidad/application/catalog/create_account.dart';
import 'package:decimal/decimal.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/ledger/factories/record_opening.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:contabilidad/domain/ports/event_store.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/domain/ports/log_filters.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:event_bus/event_bus.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:test/test.dart';

class _ThrowingEventStore implements EventStore {
  @override
  Future<bool> append(Transaction event) async {
    throw StateError('simulated event store failure');
  }

  @override
  Future<Transaction?> get(EventId id) async => null;

  @override
  Future<bool> hasReversal(EventId originalId) async => false;

  @override
  Future<List<Transaction>> queryLog({LogFilters? filters}) async => [];

  @override
  Future<List<String>> queryRawPayloads({LogFilters? filters}) async => [];
}

void main() {
  group('CreateAccount', () {
    late InMemoryEventStore store;
    late InMemoryLedgerProjections projections;
    late InMemoryCatalogRepository catalog;
    late CreateAccount createAccount;

    setUp(() {
      store = InMemoryEventStore();
      projections = InMemoryLedgerProjections();
      catalog = InMemoryCatalogRepository();

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

      createAccount = CreateAccount(
        catalog: catalog,
        recordOpening: recordOpening,
      );
    });

    test('creates an account with no opening balance', () async {
      final id = await createAccount(
        name: 'Binance',
        nativeCurrency: CurrencyCode('USD'),
        eventId: EventId('evt-create-1'),
        deviceId: 'dev-1',
      );

      final saved = catalog.getAccount(id);
      expect(saved, isNotNull);
      expect(saved!.name, 'Binance');
      expect(saved.nativeCurrency, CurrencyCode('USD'));
      expect(saved.isArchived, isFalse);
      expect(store.events, isEmpty);
    });

    test('persists the color tag into meta', () async {
      final id = await createAccount(
        name: 'Bancamiga',
        nativeCurrency: CurrencyCode('USD'),
        colorHex: '#FF5500',
        eventId: EventId('evt-create-2'),
        deviceId: 'dev-1',
      );

      expect(catalog.getAccount(id)?.colorHex, '#FF5500');
    });

    test('a non-zero opening balance posts to the Apertura envelope through '
        'RecordOpening', () async {
      final id = await createAccount(
        name: 'Bancamiga',
        nativeCurrency: CurrencyCode('USD'),
        openingBalance: Money(
          amount: BigInt.from(20000),
          currency: CurrencyCode('USD'),
        ),
        eventId: EventId('evt-create-3'),
        deviceId: 'dev-1',
      );

      final openingEnvelope = catalog.getSystemEnvelope(EnvelopeRole.opening);
      expect(projections.accountBalance(id).usd, 20000);
      expect(projections.envelopeUsdBalance(openingEnvelope), 20000);
      expect(store.events.length, 1);
    });

    test('no opening balance means no ledger transaction is posted', () async {
      await createAccount(
        name: 'BdV',
        nativeCurrency: CurrencyCode('VES'),
        eventId: EventId('evt-create-4'),
        deviceId: 'dev-1',
      );

      expect(store.events, isEmpty);
    });

    test('a non-USD opening balance with a rate posts the USD-equivalent to '
        'the Apertura envelope', () async {
      final id = await createAccount(
        name: 'BdV',
        nativeCurrency: CurrencyCode('VES'),
        openingBalance: Money(
          amount: BigInt.from(35000),
          currency: CurrencyCode('VES'),
        ),
        openingBalanceRate: Decimal.parse('3.5'),
        eventId: EventId('evt-create-5'),
        deviceId: 'dev-1',
      );

      final openingEnvelope = catalog.getSystemEnvelope(EnvelopeRole.opening);
      expect(projections.accountBalance(id).usd, 10000);
      expect(projections.envelopeUsdBalance(openingEnvelope), 10000);
    });

    test('a non-USD opening balance without a rate is rejected before the '
        'account is persisted', () async {
      expect(
        () => createAccount(
          name: 'BdV',
          nativeCurrency: CurrencyCode('VES'),
          openingBalance: Money(
            amount: BigInt.from(35000),
            currency: CurrencyCode('VES'),
          ),
          eventId: EventId('evt-create-6'),
          deviceId: 'dev-1',
        ),
        throwsArgumentError,
      );

      expect(catalog.accounts, isEmpty);
      expect(store.events, isEmpty);
    });

    test('a retroactive opening records the transaction at the fact date, '
        'not now', () async {
      final pastDate = DomainTimestamp(DateTime.utc(2026, 7, 1));

      await createAccount(
        name: 'BdV',
        nativeCurrency: CurrencyCode('VES'),
        openingBalance: Money(
          amount: BigInt.from(35000),
          currency: CurrencyCode('VES'),
        ),
        openingBalanceRate: Decimal.parse('3.5'),
        eventId: EventId('evt-create-retroactive'),
        deviceId: 'dev-1',
        occurredAt: pastDate,
      );

      expect(store.events.single.metadata.occurredAt, pastDate);
    });

    test('a RecordOpening failure after the account is saved compensates by '
        'deleting the account and re-throws', () async {
      final throwingStore = _ThrowingEventStore();
      final throwingRecordTransaction = RecordTransaction(
        store: throwingStore,
        projections: projections,
        eventBus: SyncEventBus(),
        validator: ReferentialIntegrityValidator(catalog),
      );
      final throwingRecordOpening = RecordOpening(
        record: throwingRecordTransaction,
        catalog: catalog,
        projections: projections,
      );
      final createAccountWithFailingOpening = CreateAccount(
        catalog: catalog,
        recordOpening: throwingRecordOpening,
      );

      await expectLater(
        () => createAccountWithFailingOpening(
          name: 'Bancamiga',
          nativeCurrency: CurrencyCode('USD'),
          openingBalance: Money(
            amount: BigInt.from(20000),
            currency: CurrencyCode('USD'),
          ),
          eventId: EventId('evt-create-fail'),
          deviceId: 'dev-1',
        ),
        throwsA(isA<StateError>()),
      );

      expect(catalog.accounts, isEmpty);
    });
  });
}
