import 'package:contabilidad/application/catalog/exceptions.dart';
import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/ledger/factories/record_realization.dart';
import 'package:contabilidad/application/ledger/factories/record_usd_expense.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:cuentaria_app/features/capture/application/quick_add_expense_use_case.dart';
import 'package:cuentaria_app/features/capture/application/rate_exceptions.dart';
import 'package:decimal/decimal.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/domain/rate_observation.dart';
import 'package:tasas/infrastructure/in_memory/in_memory_rate_series.dart';

void main() {
  group('QuickAddExpenseUseCase', () {
    late InMemoryEventStore store;
    late InMemoryLedgerProjections projections;
    late InMemoryCatalogRepository catalog;
    late InMemoryRateSeries rateSeries;
    late QuickAddExpenseUseCase useCase;

    late AccountId usdAccountId;
    late AccountId vesAccountId;
    late EnvelopeId envelopeId;

    setUp(() {
      store = InMemoryEventStore();
      projections = InMemoryLedgerProjections();
      catalog = InMemoryCatalogRepository();
      rateSeries = InMemoryRateSeries();

      final validator = ReferentialIntegrityValidator(catalog);
      final record = RecordTransaction(
        store: store,
        projections: projections,
        eventBus: SyncEventBus(),
        validator: validator,
      );

      useCase = QuickAddExpenseUseCase(
        recordUsdExpense: RecordUsdExpense(record: record, catalog: catalog),
        recordRealization: RecordRealization(
          record: record,
          catalog: catalog,
          projections: projections,
        ),
        catalog: catalog,
        rateSeries: rateSeries,
      );

      usdAccountId = AccountId('acc-usd');
      catalog.saveAccount(
        Account(
          id: usdAccountId,
          name: 'USD wallet',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      vesAccountId = AccountId('acc-ves');
      catalog.saveAccount(
        Account(
          id: vesAccountId,
          name: 'Bs wallet',
          nativeCurrency: CurrencyCode('VES'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      envelopeId = EnvelopeId('env-food');
      catalog.saveEnvelope(
        Envelope(
          id: envelopeId,
          name: 'Food',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );
    });

    test('a USD account posts a plain expense', () async {
      await useCase(
        eventId: EventId('evt-1'),
        deviceId: 'dev-1',
        accountId: usdAccountId,
        envelopeId: envelopeId,
        amount: Money(amount: BigInt.from(2000), currency: CurrencyCode('USD')),
      );

      final tx = store.events.single;
      expect(tx.metadata.type, 'Expense');
      expect(projections.accountBalance(usdAccountId).usd, -2000);
      expect(projections.envelopeUsdBalance(envelopeId), -2000);
    });

    test('a Bs account posts a realization using the parallel rate', () async {
      final opening = Transaction.create(
        metadata: TransactionMetadata(
          eventId: EventId('evt-opening'),
          type: 'Opening',
          occurredAt: DomainTimestamp(DateTime.now().toUtc()),
          recordedAt: DomainTimestamp(DateTime.now().toUtc()),
          deviceId: 'dev',
          schemaVersion: 1,
        ),
        postings: [
          Posting(
            target: AccountTarget(vesAccountId),
            amountNative: Money(
              amount: BigInt.from(10000),
              currency: CurrencyCode('VES'),
            ),
            currency: CurrencyCode('VES'),
            amountUsd: 500,
          ),
          Posting(
            target: EnvelopeTarget(
              catalog.getSystemEnvelope(EnvelopeRole.opening),
            ),
            amountNative: Money(
              amount: BigInt.from(500),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: 500,
          ),
        ],
      );
      projections.apply(opening);

      await rateSeries.append(
        RateObservation(
          currency: CurrencyCode('VES'),
          nativePerUsd: Decimal.parse('20.00'),
          observedAt: DateTime.now().toUtc(),
          source: 'manual:paralelo',
        ),
      );
      await rateSeries.append(
        RateObservation(
          currency: CurrencyCode('VES'),
          nativePerUsd: Decimal.parse('999.00'),
          observedAt: DateTime.now().toUtc(),
          source: 'manual:bcv',
        ),
      );

      await useCase(
        eventId: EventId('evt-2'),
        deviceId: 'dev-1',
        accountId: vesAccountId,
        envelopeId: envelopeId,
        amount: Money(
          amount: BigInt.from(5000),
          currency: CurrencyCode('VES'),
        ), // 50 VES
      );

      final tx = store.events.single;
      expect(tx.metadata.type, 'ForeignCurrencyExpense');
      expect(tx.postings.length, 3);

      // Market value = 50 / 20 = $2.50 (250 cents) — uses the parallel rate,
      // never the BCV one (ADR-0016).
      final destination = tx.postings.firstWhere(
        (p) => p.target == EnvelopeTarget(envelopeId),
      );
      expect(destination.amountUsd, -250);
    });

    test('throws TargetNotFound for an unknown account', () async {
      await expectLater(
        () => useCase(
          eventId: EventId('evt-3'),
          deviceId: 'dev-1',
          accountId: AccountId('missing'),
          envelopeId: envelopeId,
          amount: Money(
            amount: BigInt.from(100),
            currency: CurrencyCode('USD'),
          ),
        ),
        throwsA(isA<TargetNotFound>()),
      );
    });

    test('persists the note as the memo on the recorded transaction', () async {
      await useCase(
        eventId: EventId('evt-memo-1'),
        deviceId: 'dev-1',
        accountId: usdAccountId,
        envelopeId: envelopeId,
        amount: Money(amount: BigInt.from(2000), currency: CurrencyCode('USD')),
        note: 'Coffee with a client',
      );

      final log = await store.queryLog();
      expect(log.single.metadata.memo, 'Coffee with a client');
    });

    test('does not persist an empty memo when no note is given', () async {
      await useCase(
        eventId: EventId('evt-memo-2'),
        deviceId: 'dev-1',
        accountId: usdAccountId,
        envelopeId: envelopeId,
        amount: Money(amount: BigInt.from(2000), currency: CurrencyCode('USD')),
      );

      final log = await store.queryLog();
      expect(log.single.metadata.memo, isNull);
    });

    test(
      'throws RateNotAvailable when the Bs account has no parallel rate observed',
      () async {
        await expectLater(
          () => useCase(
            eventId: EventId('evt-4'),
            deviceId: 'dev-1',
            accountId: vesAccountId,
            envelopeId: envelopeId,
            amount: Money(
              amount: BigInt.from(100),
              currency: CurrencyCode('VES'),
            ),
          ),
          throwsA(isA<RateNotAvailable>()),
        );
      },
    );
  });
}
