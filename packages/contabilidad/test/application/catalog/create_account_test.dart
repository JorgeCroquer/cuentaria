import 'package:contabilidad/application/catalog/create_account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/ledger/factories/record_opening.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:event_bus/event_bus.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:test/test.dart';

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
  });
}
