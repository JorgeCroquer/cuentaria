import 'package:decimal/decimal.dart';
import 'package:test/test.dart';
import 'package:event_bus/event_bus.dart';
import 'package:shared_kernel/shared_kernel.dart';

import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
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
        projections: projections,
      );
    });

    /// Funds [accountId] with [nativeAmount] at a frozen cost of [usdAmount]
    /// via a bare Opening posting pair, so the balance/cost basis exists
    /// without going through an Income factory.
    Future<void> fund({
      required AccountId accountId,
      required BigInt nativeAmount,
      required CurrencyCode currency,
      required int usdAmount,
    }) async {
      final differentialId = catalog.getSystemEnvelope(
        EnvelopeRole.differential,
      );
      final eventId = EventId('evt-fund-${accountId.value}');
      await store.append(
        Transaction.create(
          metadata: TransactionMetadata(
            eventId: eventId,
            type: 'Opening',
            occurredAt: DomainTimestamp(DateTime.now().toUtc()),
            recordedAt: DomainTimestamp(DateTime.now().toUtc()),
            deviceId: 'dev-1',
            schemaVersion: 1,
          ),
          postings: [
            Posting(
              target: AccountTarget(accountId),
              amountNative: Money(amount: nativeAmount, currency: currency),
              currency: currency,
              amountUsd: usdAmount,
            ),
            Posting(
              target: EnvelopeTarget(differentialId),
              amountNative: Money(
                amount: BigInt.from(usdAmount),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: usdAmount,
            ),
          ],
        ),
      );
      projections.apply((await store.get(eventId))!);
    }

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

    test('rejects a USD transfer that carries a parallel rate — USD needs no '
        'valuation', () async {
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
          eventId: EventId('evt-usd-rate'),
          deviceId: 'dev-1',
          sourceAccountId: sourceId,
          destinationAccountId: destinationId,
          amount: Money(
            amount: BigInt.from(3000),
            currency: CurrencyCode('USD'),
          ),
          parallelRate: Decimal.parse('40'),
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(store.events.isEmpty, isTrue);
    });

    group('non-USD transfer between two accounts of the same currency '
        '(ADR-0018 §3)', () {
      late AccountId bdv;
      late AccountId bancamiga;

      setUp(() {
        bdv = AccountId('bdv');
        bancamiga = AccountId('bancamiga');
        catalog.saveAccount(
          Account(
            id: bdv,
            name: 'BdV',
            nativeCurrency: CurrencyCode('VES'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );
        catalog.saveAccount(
          Account(
            id: bancamiga,
            name: 'Bancamiga',
            nativeCurrency: CurrencyCode('VES'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );
      });

      test('(a) a fully covered transfer moves the proportional frozen cost, '
          'balances stay coherent, and no rate is required', () async {
        // 10,000.00 Bs funded at a frozen cost of $50.00 (200 VES/USD).
        await fund(
          accountId: bdv,
          nativeAmount: BigInt.from(1000000),
          currency: CurrencyCode('VES'),
          usdAmount: 5000,
        );

        // Move half: 5,000.00 Bs.
        await recordTransfer(
          eventId: EventId('evt-covered'),
          deviceId: 'dev-1',
          sourceAccountId: bdv,
          destinationAccountId: bancamiga,
          amount: Money(
            amount: BigInt.from(500000),
            currency: CurrencyCode('VES'),
          ),
        );

        final tx = (await store.queryLog()).last;
        expect(tx.metadata.type, 'Transfer');
        expect(tx.postings.length, 2);

        // Proportional: half the native moved => half the frozen cost.
        expect(
          projections.accountBalance(bdv).native.amount,
          BigInt.from(500000),
        );
        expect(projections.accountBalance(bdv).usd, 2500);
        expect(
          projections.accountBalance(bancamiga).native.amount,
          BigInt.from(500000),
        );
        expect(projections.accountBalance(bancamiga).usd, 2500);
      });

      test('(b) a transfer that empties the account takes ALL remaining cost '
          'basis (zero-native rule, C1-6)', () async {
        await fund(
          accountId: bdv,
          nativeAmount: BigInt.from(500000),
          currency: CurrencyCode('VES'),
          usdAmount: 1000,
        );

        await recordTransfer(
          eventId: EventId('evt-empties'),
          deviceId: 'dev-1',
          sourceAccountId: bdv,
          destinationAccountId: bancamiga,
          amount: Money(
            amount: BigInt.from(500000),
            currency: CurrencyCode('VES'),
          ),
        );

        expect(projections.accountBalance(bdv).native.amount, BigInt.zero);
        expect(projections.accountBalance(bdv).usd, 0);
        expect(projections.accountBalance(bancamiga).usd, 1000);
      });

      test('(c) an excess above the known balance is valued at the parallel '
          'rate on top of the proportional frozen cost, with no differential '
          'posting', () async {
        // Traced example from the doctrine session: 5,000.00 Bs at $10.00
        // frozen cost, moving 20,000.00 Bs with the series at 400.00
        // VES/USD.
        await fund(
          accountId: bdv,
          nativeAmount: BigInt.from(500000),
          currency: CurrencyCode('VES'),
          usdAmount: 1000,
        );

        await recordTransfer(
          eventId: EventId('evt-excess'),
          deviceId: 'dev-1',
          sourceAccountId: bdv,
          destinationAccountId: bancamiga,
          amount: Money(
            amount: BigInt.from(2000000),
            currency: CurrencyCode('VES'),
          ),
          parallelRate: Decimal.parse('400'),
        );

        final tx = (await store.queryLog()).last;
        expect(tx.postings.length, 2);
        // cubierto 5,000.00 => $10.00; exceso 15,000.00 / 400 = $37.50.
        // costo movido = $47.50, on top of BdV's existing $10.00 balance.
        expect(
          projections.accountBalance(bdv).native.amount,
          BigInt.from(-1500000),
        );
        expect(projections.accountBalance(bdv).usd, 1000 - 4750);
        expect(projections.accountBalance(bancamiga).usd, 4750);

        for (final posting in tx.postings) {
          expect(posting.rateRef, '400.00 VES/USD');
        }
      });

      test('(d) an excess without a parallel rate throws a domain exception '
          'and posts nothing', () async {
        await fund(
          accountId: bdv,
          nativeAmount: BigInt.from(500000),
          currency: CurrencyCode('VES'),
          usdAmount: 1000,
        );

        await expectLater(
          () => recordTransfer(
            eventId: EventId('evt-excess-no-rate'),
            deviceId: 'dev-1',
            sourceAccountId: bdv,
            destinationAccountId: bancamiga,
            amount: Money(
              amount: BigInt.from(2000000),
              currency: CurrencyCode('VES'),
            ),
          ),
          throwsA(isA<RateRequiredForExcess>()),
        );

        // Only the funding event exists — the failed transfer posted
        // nothing.
        expect(store.events.length, 1);
      });

      test('(e) a source with an already-negative balance covers nothing — the '
          'entire moved amount is excess', () async {
        // No funding at all: the account starts at zero, so a transfer
        // pushes it straight into negative territory.
        await recordTransfer(
          eventId: EventId('evt-all-excess'),
          deviceId: 'dev-1',
          sourceAccountId: bdv,
          destinationAccountId: bancamiga,
          amount: Money(
            amount: BigInt.from(400000),
            currency: CurrencyCode('VES'),
          ),
          parallelRate: Decimal.parse('400'),
        );

        // 4,000.00 / 400 = $10.00, all excess, no covered cost.
        expect(projections.accountBalance(bdv).usd, -1000);
        expect(projections.accountBalance(bancamiga).usd, 1000);
      });
    });

    test('rejects transfer to the same account', () async {
      final accountId = AccountId('acc-usd-1');

      catalog.saveAccount(
        Account(
          id: accountId,
          name: 'USD Account 1',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      await expectLater(
        () => recordTransfer(
          eventId: EventId('evt-same'),
          deviceId: 'dev-1',
          sourceAccountId: accountId,
          destinationAccountId: accountId,
          amount: Money(
            amount: BigInt.from(3000),
            currency: CurrencyCode('USD'),
          ),
        ),
        throwsA(isA<ArgumentError>()),
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
