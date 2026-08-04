import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/ledger/exceptions.dart';
import 'package:contabilidad/application/ledger/factories/record_acquisition_conversion.dart';
import 'package:contabilidad/application/ledger/factories/record_income.dart';
import 'package:contabilidad/application/ledger/factories/record_realization.dart';
import 'package:contabilidad/application/ledger/factories/record_transfer.dart';
import 'package:contabilidad/application/ledger/factories/record_usd_expense.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:cuentaria_app/features/capture/application/quick_add_expense_use_case.dart';
import 'package:cuentaria_app/features/capture/application/quick_add_income_use_case.dart';
import 'package:cuentaria_app/features/capture/application/quick_add_mover_use_case.dart';
import 'package:decimal/decimal.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/domain/rate_observation.dart';
import 'package:tasas/infrastructure/in_memory/in_memory_rate_series.dart';

/// Closes the re-drain gap (criterion 11): the nine rows of the ADR-0018 §
/// "Matriz de derivación resultante" table, each driven end to end through
/// the same three capture use cases the sheet calls (U1, PRD #92) — never
/// the factories directly, since it's the use case that resolves the rate
/// the sheet would otherwise supply. Every reachable row must post; the one
/// unreachable pair (foreign -> a *different* foreign) must fail with a
/// typed exception and post nothing, matching what the UI's chip guard
/// (#116) already keeps the user from forming.
void main() {
  group('Quick-add matrix — all nine rows of ADR-0018 §3', () {
    late InMemoryEventStore store;
    late InMemoryLedgerProjections projections;
    late InMemoryCatalogRepository catalog;
    late InMemoryRateSeries rateSeries;
    late QuickAddExpenseUseCase expenseUseCase;
    late QuickAddIncomeUseCase incomeUseCase;
    late QuickAddMoverUseCase moverUseCase;

    late EnvelopeId envelopeId;

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

    setUp(() async {
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

      expenseUseCase = QuickAddExpenseUseCase(
        recordUsdExpense: RecordUsdExpense(record: record, catalog: catalog),
        recordRealization: RecordRealization(
          record: record,
          catalog: catalog,
          projections: projections,
        ),
        catalog: catalog,
        rateSeries: rateSeries,
      );

      incomeUseCase = QuickAddIncomeUseCase(
        recordIncome: RecordIncome(record: record, catalog: catalog),
        catalog: catalog,
        rateSeries: rateSeries,
      );

      moverUseCase = QuickAddMoverUseCase(
        recordTransfer: RecordTransfer(
          record: record,
          catalog: catalog,
          projections: projections,
        ),
        recordAcquisitionConversion: RecordAcquisitionConversion(
          record: record,
          catalog: catalog,
        ),
        recordRealization: RecordRealization(
          record: record,
          catalog: catalog,
          projections: projections,
        ),
        catalog: catalog,
        rateSeries: rateSeries,
      );

      addAccount('acc-usd', 'USD');
      addAccount('acc-usd-2', 'USD');
      addAccount('acc-ves', 'VES');
      addAccount('acc-ves-2', 'VES');
      addAccount('acc-eur', 'EUR');

      envelopeId = EnvelopeId('env-food');
      await catalog.saveEnvelope(
        Envelope(
          id: envelopeId,
          name: 'Food',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      await rateSeries.append(
        RateObservation(
          currency: CurrencyCode('VES'),
          nativePerUsd: Decimal.parse('40.00'),
          observedAt: DateTime.now().toUtc(),
          source: 'manual:paralelo',
        ),
      );
    });

    test('row 1: Gasto USD posts a plain USD expense', () async {
      await expenseUseCase(
        eventId: EventId('evt-row1'),
        deviceId: 'dev-1',
        accountId: AccountId('acc-usd'),
        envelopeId: envelopeId,
        amount: Money(amount: BigInt.from(1000), currency: CurrencyCode('USD')),
      );

      final log = await store.queryLog();
      expect(log.single.metadata.type, 'Expense');
    });

    test('row 2: Gasto Bs posts a foreign-currency realization valued at the '
        'parallel rate', () async {
      await expenseUseCase(
        eventId: EventId('evt-row2'),
        deviceId: 'dev-1',
        accountId: AccountId('acc-ves'),
        envelopeId: envelopeId,
        amount: Money(
          amount: BigInt.from(40000),
          currency: CurrencyCode('VES'),
        ),
      );

      final log = await store.queryLog();
      expect(log.single.metadata.type, 'ForeignCurrencyExpense');
    });

    test('row 3: Ingreso to a USD account posts a plain income', () async {
      await incomeUseCase(
        eventId: EventId('evt-row3'),
        deviceId: 'dev-1',
        accountId: AccountId('acc-usd'),
        amount: Money(amount: BigInt.from(1000), currency: CurrencyCode('USD')),
        source: 'Cliente',
      );

      final log = await store.queryLog();
      expect(log.single.metadata.type, 'Income');
    });

    test('row 4: Ingreso to a Bs account posts an income valued at the '
        'parallel rate', () async {
      await incomeUseCase(
        eventId: EventId('evt-row4'),
        deviceId: 'dev-1',
        accountId: AccountId('acc-ves'),
        amount: Money(
          amount: BigInt.from(40000),
          currency: CurrencyCode('VES'),
        ),
        source: 'Cliente Bs',
      );

      final log = await store.queryLog();
      expect(log.single.metadata.type, 'Income');
      expect(projections.accountBalance(AccountId('acc-ves')).usd, 1000);
    });

    test('row 5: Mover USD -> USD posts a plain Transfer', () async {
      await moverUseCase(
        eventId: EventId('evt-row5'),
        deviceId: 'dev-1',
        sourceAccountId: AccountId('acc-usd'),
        destinationAccountId: AccountId('acc-usd-2'),
        givenAmount: Money(
          amount: BigInt.from(1000),
          currency: CurrencyCode('USD'),
        ),
      );

      final log = await store.queryLog();
      expect(log.single.metadata.type, 'Transfer');
    });

    test('row 6: Mover USD -> Bs posts an AcquisitionConversion', () async {
      await moverUseCase(
        eventId: EventId('evt-row6'),
        deviceId: 'dev-1',
        sourceAccountId: AccountId('acc-usd'),
        destinationAccountId: AccountId('acc-ves'),
        givenAmount: Money(
          amount: BigInt.from(1000),
          currency: CurrencyCode('USD'),
        ),
        rate: Decimal.parse('40'),
      );

      final log = await store.queryLog();
      expect(log.single.metadata.type, 'AcquisitionConversion');
    });

    test('row 7: Mover Bs -> USD posts a DisposalConversion', () async {
      await moverUseCase(
        eventId: EventId('evt-row7'),
        deviceId: 'dev-1',
        sourceAccountId: AccountId('acc-ves'),
        destinationAccountId: AccountId('acc-usd'),
        givenAmount: Money(
          amount: BigInt.from(40000),
          currency: CurrencyCode('VES'),
        ),
        rate: Decimal.parse('40'),
      );

      final log = await store.queryLog();
      expect(log.single.metadata.type, 'DisposalConversion');
    });

    test('row 8: Mover Bs -> a different Bs account posts a Transfer valued '
        'via the parallel rate for any excess', () async {
      await moverUseCase(
        eventId: EventId('evt-row8'),
        deviceId: 'dev-1',
        sourceAccountId: AccountId('acc-ves'),
        destinationAccountId: AccountId('acc-ves-2'),
        givenAmount: Money(
          amount: BigInt.from(40000),
          currency: CurrencyCode('VES'),
        ),
      );

      final log = await store.queryLog();
      expect(log.single.metadata.type, 'Transfer');
      expect(projections.accountBalance(AccountId('acc-ves-2')).usd, 1000);
    });

    test('row 9: Mover Bs -> EUR (different foreign currencies) is not '
        'modeled by any factory (ADR-0018 §5) — the UI chip guard keeps this '
        'pair from being reachable, and if invoked directly it throws a typed '
        'exception and posts nothing', () async {
      await expectLater(
        () => moverUseCase(
          eventId: EventId('evt-row9'),
          deviceId: 'dev-1',
          sourceAccountId: AccountId('acc-ves'),
          destinationAccountId: AccountId('acc-eur'),
          givenAmount: Money(
            amount: BigInt.from(40000),
            currency: CurrencyCode('VES'),
          ),
          rate: Decimal.parse('40'),
        ),
        throwsA(isA<UsdOnlyOperation>()),
      );

      expect(await store.queryLog(), isEmpty);
    });

    test('invariant: none of the nine rows throws an untyped exception without '
        'posting — each reachable row lands a transaction, and the one '
        'unreachable row fails with the same typed UsdOnlyOperation the UI '
        'already catches and displays', () async {
      final rows = <Future<void> Function()>[
        () => expenseUseCase(
          eventId: EventId('evt-inv-1'),
          deviceId: 'dev-1',
          accountId: AccountId('acc-usd'),
          envelopeId: envelopeId,
          amount: Money(
            amount: BigInt.from(1000),
            currency: CurrencyCode('USD'),
          ),
        ),
        () => expenseUseCase(
          eventId: EventId('evt-inv-2'),
          deviceId: 'dev-1',
          accountId: AccountId('acc-ves'),
          envelopeId: envelopeId,
          amount: Money(
            amount: BigInt.from(40000),
            currency: CurrencyCode('VES'),
          ),
        ),
        () => incomeUseCase(
          eventId: EventId('evt-inv-3'),
          deviceId: 'dev-1',
          accountId: AccountId('acc-usd'),
          amount: Money(
            amount: BigInt.from(1000),
            currency: CurrencyCode('USD'),
          ),
          source: 'Cliente',
        ),
        () => incomeUseCase(
          eventId: EventId('evt-inv-4'),
          deviceId: 'dev-1',
          accountId: AccountId('acc-ves'),
          amount: Money(
            amount: BigInt.from(40000),
            currency: CurrencyCode('VES'),
          ),
          source: 'Cliente Bs',
        ),
        () => moverUseCase(
          eventId: EventId('evt-inv-5'),
          deviceId: 'dev-1',
          sourceAccountId: AccountId('acc-usd'),
          destinationAccountId: AccountId('acc-usd-2'),
          givenAmount: Money(
            amount: BigInt.from(1000),
            currency: CurrencyCode('USD'),
          ),
        ),
        () => moverUseCase(
          eventId: EventId('evt-inv-6'),
          deviceId: 'dev-1',
          sourceAccountId: AccountId('acc-usd'),
          destinationAccountId: AccountId('acc-ves'),
          givenAmount: Money(
            amount: BigInt.from(1000),
            currency: CurrencyCode('USD'),
          ),
          rate: Decimal.parse('40'),
        ),
        () => moverUseCase(
          eventId: EventId('evt-inv-7'),
          deviceId: 'dev-1',
          sourceAccountId: AccountId('acc-ves'),
          destinationAccountId: AccountId('acc-usd'),
          givenAmount: Money(
            amount: BigInt.from(40000),
            currency: CurrencyCode('VES'),
          ),
          rate: Decimal.parse('40'),
        ),
        () => moverUseCase(
          eventId: EventId('evt-inv-8'),
          deviceId: 'dev-1',
          sourceAccountId: AccountId('acc-ves'),
          destinationAccountId: AccountId('acc-ves-2'),
          givenAmount: Money(
            amount: BigInt.from(40000),
            currency: CurrencyCode('VES'),
          ),
        ),
        () => moverUseCase(
          eventId: EventId('evt-inv-9'),
          deviceId: 'dev-1',
          sourceAccountId: AccountId('acc-ves'),
          destinationAccountId: AccountId('acc-eur'),
          givenAmount: Money(
            amount: BigInt.from(40000),
            currency: CurrencyCode('VES'),
          ),
          rate: Decimal.parse('40'),
        ),
      ];

      var posted = 0;
      var typedFailures = 0;

      for (var i = 0; i < rows.length; i++) {
        try {
          await rows[i]();
          posted++;
        } catch (e) {
          expect(
            e,
            isA<UsdOnlyOperation>(),
            reason:
                'row ${i + 1} threw an unexpected, unexplained '
                'exception: $e',
          );
          typedFailures++;
        }
      }

      // Rows 1-8 post, row 9 fails typed.
      expect(posted, 8);
      expect(typedFailures, 1);
      expect((await store.queryLog()).length, 8);
    });
  });
}
