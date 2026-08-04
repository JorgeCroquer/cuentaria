import 'package:decimal/decimal.dart';
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
import 'package:contabilidad/application/ledger/factories/record_income.dart';

void main() {
  group('RecordIncome', () {
    late InMemoryEventStore store;
    late InMemoryLedgerProjections projections;
    late SyncEventBus eventBus;
    late InMemoryCatalogRepository catalog;
    late RecordTransaction recordTransaction;
    late RecordIncome recordIncome;

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

      recordIncome = RecordIncome(record: recordTransaction, catalog: catalog);
    });

    test('income to USD account with implicit Stage envelope', () async {
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

      final stageId = catalog.getSystemEnvelope(EnvelopeRole.stage);

      await recordIncome(
        eventId: EventId('evt-1'),
        deviceId: 'dev-1',
        accountId: accountId,
        amount: Money(
          amount: BigInt.from(15000),
          currency: CurrencyCode('USD'),
        ), // 150 USD
        source: 'Client A',
      );

      expect(store.events.length, equals(1));
      final tx = store.events.first;
      expect(tx.metadata.type, equals('Income'));
      expect(tx.metadata.source, equals('Client A'));

      expect(projections.accountBalance(accountId).usd, equals(15000));
      expect(projections.envelopeUsdBalance(stageId), equals(15000));
    });

    test('income to USD account with explicit envelope', () async {
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

      final destinationEnvelopeId = EnvelopeId('env-travel');
      catalog.saveEnvelope(
        Envelope(
          id: destinationEnvelopeId,
          name: 'Travel',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      await recordIncome(
        eventId: EventId('evt-1'),
        deviceId: 'dev-1',
        accountId: accountId,
        envelopeId: destinationEnvelopeId,
        amount: Money(
          amount: BigInt.from(15000),
          currency: CurrencyCode('USD'),
        ), // 150 USD
        source: 'Client A',
      );

      expect(projections.accountBalance(accountId).usd, equals(15000));
      expect(
        projections.envelopeUsdBalance(destinationEnvelopeId),
        equals(15000),
      );
    });

    test('income to a foreign currency account values it with the given rate, '
        'in a single rounding, and stages the USD equivalent — no differential '
        'posting (ADR-0018)', () async {
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
      final stageId = catalog.getSystemEnvelope(EnvelopeRole.stage);

      await recordIncome(
        eventId: EventId('evt-fx'),
        deviceId: 'dev-1',
        accountId: accountId,
        amount: Money(
          amount: BigInt.from(2000000),
          currency: CurrencyCode('VES'),
        ), // 20000.00 Bs
        source: 'Cliente Bs',
        currentRate: Decimal.parse('100'),
      );

      final tx = store.events.single;
      expect(tx.metadata.type, 'Income');
      expect(tx.metadata.source, 'Cliente Bs');
      expect(tx.postings.length, 2);

      final accountPosting = tx.postings.first;
      expect(accountPosting.amountUsd, 20000); // 20000.00 / 100 = $200.00
      expect(accountPosting.rateRef, '100.00 VES/USD');
      expect(accountPosting.currency, CurrencyCode('VES'));

      final envelopePosting = tx.postings.last;
      expect(envelopePosting.amountUsd, 20000);
      expect(envelopePosting.currency, CurrencyCode('USD'));

      expect(
        projections.accountBalance(accountId).native.amount,
        BigInt.from(2000000),
      );
      expect(projections.accountBalance(accountId).usd, 20000);
      expect(projections.envelopeUsdBalance(stageId), 20000);
    });

    test(
      'income to a foreign currency account without a rate throws',
      () async {
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

        await expectLater(
          () => recordIncome(
            eventId: EventId('evt-2'),
            deviceId: 'dev-1',
            accountId: accountId,
            amount: Money(
              amount: BigInt.from(500),
              currency: CurrencyCode('VES'),
            ),
            source: 'Client B',
          ),
          throwsA(isA<ArgumentError>()),
        );

        expect(store.events.isEmpty, isTrue);
      },
    );

    test('income to a USD account with a rate throws — a USD account is '
        'never valued', () async {
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
        () => recordIncome(
          eventId: EventId('evt-3'),
          deviceId: 'dev-1',
          accountId: accountId,
          amount: Money(
            amount: BigInt.from(500),
            currency: CurrencyCode('USD'),
          ),
          source: 'Client C',
          currentRate: Decimal.parse('40'),
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(store.events.isEmpty, isTrue);
    });

    test('income rejects negative or zero amount', () async {
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
        () => recordIncome(
          eventId: EventId('evt-4'),
          deviceId: 'dev-1',
          accountId: accountId,
          amount: Money(
            amount: BigInt.from(-15000),
            currency: CurrencyCode('USD'),
          ),
          source: 'Client D',
        ),
        throwsA(isA<ArgumentError>()),
      );

      await expectLater(
        () => recordIncome(
          eventId: EventId('evt-5'),
          deviceId: 'dev-1',
          accountId: accountId,
          amount: Money(amount: BigInt.from(0), currency: CurrencyCode('USD')),
          source: 'Client E',
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(store.events.isEmpty, isTrue);
    });
  });
}
