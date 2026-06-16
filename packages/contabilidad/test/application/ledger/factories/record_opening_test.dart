import 'package:test/test.dart';
import 'package:decimal/decimal.dart';
import 'package:event_bus/event_bus.dart';
import 'package:shared_kernel/shared_kernel.dart';

import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/application/catalog/exceptions.dart';
import 'package:contabilidad/application/ledger/factories/record_opening.dart';
import 'package:contabilidad/application/ledger/factories/record_distribution.dart';

void main() {
  group('RecordOpening', () {
    late InMemoryEventStore store;
    late InMemoryLedgerProjections projections;
    late SyncEventBus eventBus;
    late InMemoryCatalogRepository catalog;
    late RecordTransaction recordTransaction;
    late RecordOpening recordOpening;

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

      recordOpening = RecordOpening(
        record: recordTransaction,
        catalog: catalog,
        projections: projections,
      );
    });

    test('USD account uses nativeAmount directly', () async {
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

      await recordOpening(
        eventId: EventId('evt-1'),
        deviceId: 'dev-1',
        accountId: accountId,
        nativeAmount: Money(
          amount: BigInt.from(10000),
          currency: CurrencyCode('USD'),
        ),
      );

      expect(store.events.length, equals(1));
      final tx = store.events.first;
      expect(tx.metadata.type, equals('Opening'));

      final sysOpeningId = catalog.getSystemEnvelope(EnvelopeRole.opening);

      // Projections
      expect(projections.accountBalance(accountId).usd, equals(10000));
      expect(projections.envelopeUsdBalance(sysOpeningId), equals(10000));

      // Postings check
      expect(tx.postings.length, equals(2));
      final pAccount = tx.postings.firstWhere((p) => p.target is AccountTarget);
      final pEnvelope = tx.postings.firstWhere(
        (p) => p.target is EnvelopeTarget,
      );

      expect(pAccount.amountUsd, equals(10000));
      expect(pAccount.amountNative.amount, equals(BigInt.from(10000)));

      expect(pEnvelope.amountUsd, equals(10000));
    });

    test('foreign account with amountUsd uses amountUsd directly', () async {
      final accountId = AccountId('acc-ext');
      catalog.saveAccount(
        Account(
          id: accountId,
          name: 'EUR Account',
          nativeCurrency: CurrencyCode('EUR'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      await recordOpening(
        eventId: EventId('evt-2'),
        deviceId: 'dev-1',
        accountId: accountId,
        nativeAmount: Money(
          amount: BigInt.from(10000),
          currency: CurrencyCode('EUR'),
        ),
        amountUsd: 11000,
      );

      final sysOpeningId = catalog.getSystemEnvelope(EnvelopeRole.opening);
      expect(projections.accountBalance(accountId).usd, equals(11000));
      expect(projections.envelopeUsdBalance(sysOpeningId), equals(11000));
    });

    test(
      'foreign account with rate calculates usd with decimal precision',
      () async {
        final accountId = AccountId('acc-ext-2');
        catalog.saveAccount(
          Account(
            id: accountId,
            name: 'VES Account',
            nativeCurrency: CurrencyCode('VES'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        await recordOpening(
          eventId: EventId('evt-3'),
          deviceId: 'dev-1',
          accountId: accountId,
          nativeAmount: Money(
            amount: BigInt.from(10000),
            currency: CurrencyCode('VES'),
          ),
          rate: Decimal.parse('40.0'), // 10000 / 40.0 = 250
        );

        final sysOpeningId = catalog.getSystemEnvelope(EnvelopeRole.opening);
        expect(projections.accountBalance(accountId).usd, equals(250));
        expect(projections.envelopeUsdBalance(sysOpeningId), equals(250));
      },
    );

    test(
      'rejects non-existent account, missing foreign param, and re-opening',
      () async {
        final accountId = AccountId('acc-ext-3');

        // 1. Target not found
        await expectLater(
          () => recordOpening(
            eventId: EventId('evt-4'),
            deviceId: 'dev-1',
            accountId: accountId,
            nativeAmount: Money(
              amount: BigInt.from(100),
              currency: CurrencyCode('EUR'),
            ),
          ),
          throwsA(isA<TargetNotFound>()),
        );

        catalog.saveAccount(
          Account(
            id: accountId,
            name: 'EUR Account 3',
            nativeCurrency: CurrencyCode('EUR'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        // 2. Foreign without amountUsd or rate
        await expectLater(
          () => recordOpening(
            eventId: EventId('evt-5'),
            deviceId: 'dev-1',
            accountId: accountId,
            nativeAmount: Money(
              amount: BigInt.from(100),
              currency: CurrencyCode('EUR'),
            ),
          ),
          throwsA(isA<ArgumentError>()),
        );

        // 3. Re-opening
        await recordOpening(
          eventId: EventId('evt-6'),
          deviceId: 'dev-1',
          accountId: accountId,
          nativeAmount: Money(
            amount: BigInt.from(100),
            currency: CurrencyCode('EUR'),
          ),
          amountUsd: 110,
        );

        await expectLater(
          () => recordOpening(
            eventId: EventId('evt-7'),
            deviceId: 'dev-1',
            accountId: accountId,
            nativeAmount: Money(
              amount: BigInt.from(100),
              currency: CurrencyCode('EUR'),
            ),
            amountUsd: 110,
          ),
          throwsA(isA<ArgumentError>()), // Guard trigger
        );
      },
    );
  });

  group('Opening + Distribution Integration', () {
    test(
      'Records opening and then distributes leaving opening at zero',
      () async {
        final store = InMemoryEventStore();
        final projections = InMemoryLedgerProjections();
        final eventBus = SyncEventBus();
        final catalog = InMemoryCatalogRepository();

        final validator = ReferentialIntegrityValidator(catalog);
        final recordTransaction = RecordTransaction(
          store: store,
          projections: projections,
          eventBus: eventBus,
          validator: validator,
        );

        final recordOpening = RecordOpening(
          record: recordTransaction,
          catalog: catalog,
          projections: projections,
        );

        final recordDistribution = RecordDistribution(
          record: recordTransaction,
          catalog: catalog,
        );

        final sysOpeningId = catalog.getSystemEnvelope(EnvelopeRole.opening);
        final accountId = AccountId('acc-usd-int');
        catalog.saveAccount(
          Account(
            id: accountId,
            name: 'USD Int',
            nativeCurrency: CurrencyCode('USD'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        final env1 = EnvelopeId('env-int-1');
        final env2 = EnvelopeId('env-int-2');
        catalog.saveEnvelope(
          Envelope(
            id: env1,
            name: 'E1',
            role: EnvelopeRole.none,
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );
        catalog.saveEnvelope(
          Envelope(
            id: env2,
            name: 'E2',
            role: EnvelopeRole.none,
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        // 1. Opening
        await recordOpening(
          eventId: EventId('evt-int-1'),
          deviceId: 'dev-1',
          accountId: accountId,
          nativeAmount: Money(
            amount: BigInt.from(300),
            currency: CurrencyCode('USD'),
          ),
        );

        expect(projections.envelopeUsdBalance(sysOpeningId), equals(300));

        // 2. Distribution
        final entries = [
          DistributionEntry(envelopeId: sysOpeningId, amountUsd: -300),
          DistributionEntry(envelopeId: env1, amountUsd: 200),
          DistributionEntry(envelopeId: env2, amountUsd: 100),
        ];

        await recordDistribution(
          eventId: EventId('evt-int-2'),
          deviceId: 'dev-1',
          entries: entries,
        );

        // 3. Validate
        expect(projections.envelopeUsdBalance(sysOpeningId), equals(0));
        expect(projections.envelopeUsdBalance(env1), equals(200));
        expect(projections.envelopeUsdBalance(env2), equals(100));
        expect(projections.accountBalance(accountId).usd, equals(300));
      },
    );
  });
}
