import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/ledger/factories/record_adjustment.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/reconciliation/reconciliation_planner.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:cuentaria_app/features/reconciliation/application/mark_account_reconciled.dart';
import 'package:cuentaria_app/features/reconciliation/application/reconcile_use_case.dart';
import 'package:decimal/decimal.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/domain/rate_observation.dart';
import 'package:tasas/infrastructure/in_memory/in_memory_rate_series.dart';

/// C3 Reconciliation ritual applied to a Debt Account (#209, ADR-0022 §4):
/// "Conciliar" declares Splitwise's net for a person, exactly as it would for
/// a liquid Cuenta — the ritual is not widened, the same [ReconcileUseCase]
/// runs against a Catalog Account tagged with a `counterpartyName`. Crossing
/// zero is legal overdraft (ADR-0017) and must post correctly in both
/// directions and in the account's own pact currency.
void main() {
  group('ReconcileUseCase on a Debt Account', () {
    late InMemoryEventStore store;
    late InMemoryLedgerProjections projections;
    late InMemoryCatalogRepository catalog;
    late InMemoryRateSeries rateSeries;
    late ReconcileUseCase useCase;
    late EnvelopeId adjustmentsId;

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

      useCase = ReconcileUseCase(
        recordAdjustment: RecordAdjustment(
          record: record,
          projections: projections,
          catalog: catalog,
        ),
        catalog: catalog,
        projections: projections,
        rateSeries: rateSeries,
        markReconciled: MarkAccountReconciled(catalog: catalog),
      );

      adjustmentsId = catalog.getSystemEnvelope(EnvelopeRole.adjustments);
    });

    test(
      'Claudia (USD): declaring \$37,00, then -\$12,00 (crossing zero), '
      'then \$0,00 posts each adjustment and leaves the balance at zero',
      () async {
        final claudiaId = AccountId('claudia-usd');
        await catalog.saveAccount(
          Account(
            id: claudiaId,
            name: 'Claudia',
            nativeCurrency: CurrencyCode('USD'),
            isArchived: false,
            updatedAt: DateTime.now(),
            meta: {'counterpartyName': 'Claudia'},
          ),
        );

        // Declares "Claudia te debe $37,00" — a routed surplus (the delta
        // exceeds the $1.00 tolerance, ADR-0019 §1), forced through exactly
        // as the sheet's "Absorber de todos modos" escape hatch would.
        final first = await useCase(
          eventId: EventId('evt-claudia-1'),
          deviceId: 'dev-1',
          accountId: claudiaId,
          realNativeBalance: Money(
            amount: BigInt.from(3700),
            currency: CurrencyCode('USD'),
          ),
          forceAbsorb: true,
        );
        expect(first, isA<RouteToIncome>());
        expect(projections.accountBalance(claudiaId).usd, 3700);

        // Declares "le debés $12,00 a Claudia": crosses zero.
        final second = await useCase(
          eventId: EventId('evt-claudia-2'),
          deviceId: 'dev-1',
          accountId: claudiaId,
          realNativeBalance: Money(
            amount: BigInt.from(-1200),
            currency: CurrencyCode('USD'),
          ),
          forceAbsorb: true,
        );
        expect(second, isA<RouteToExpense>());
        expect(projections.accountBalance(claudiaId).usd, -1200);

        // Declares \$0,00 — the zero balance a Splitwise settle-up produces.
        final third = await useCase(
          eventId: EventId('evt-claudia-3'),
          deviceId: 'dev-1',
          accountId: claudiaId,
          realNativeBalance: Money(
            amount: BigInt.zero,
            currency: CurrencyCode('USD'),
          ),
          forceAbsorb: true,
        );
        expect(third, isA<RouteToIncome>());
        expect(projections.accountBalance(claudiaId).usd, 0);
        expect(projections.envelopeUsdBalance(adjustmentsId), 0);
        expect(catalog.getAccount(claudiaId)!.lastReconciledAt, isNotNull);
      },
    );

    test(
      'Claudia (VES): a fresh debt account crossing straight into overdraft '
      'values the excess at the observed rate, on the declared fact date',
      () async {
        await rateSeries.append(
          RateObservation(
            currency: CurrencyCode('VES'),
            nativePerUsd: Decimal.parse('100'),
            observedAt: DateTime.utc(2026, 8, 20),
            source: 'manual:paralelo',
          ),
        );

        final claudiaId = AccountId('claudia-ves');
        await catalog.saveAccount(
          Account(
            id: claudiaId,
            name: 'Claudia',
            nativeCurrency: CurrencyCode('VES'),
            isArchived: false,
            updatedAt: DateTime.now(),
            meta: {'counterpartyName': 'Claudia'},
          ),
        );

        final occurredAt = DomainTimestamp(DateTime.utc(2026, 8, 20));
        final outcome = await useCase(
          eventId: EventId('evt-claudia-ves-1'),
          deviceId: 'dev-1',
          accountId: claudiaId,
          realNativeBalance: Money(
            amount: BigInt.from(-3000),
            currency: CurrencyCode('VES'),
          ),
          occurredAt: occurredAt,
        );

        // -3000 VES / 100 VES per USD = -$0.30: within the $1.00 tolerance.
        expect(outcome, isA<Absorb>());
        final tx = store.events.single;
        expect(tx.metadata.occurredAt, occurredAt);
        final pAcc = tx.postings.firstWhere((p) => p.target is AccountTarget);
        expect(pAcc.amountNative.amount, BigInt.from(-3000));
        expect(pAcc.amountUsd, -30);

        expect(
          projections.accountBalance(claudiaId).native.amount,
          BigInt.from(-3000),
        );
        expect(projections.accountBalance(claudiaId).usd, -30);
      },
    );
  });
}
