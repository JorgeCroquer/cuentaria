/// F4 faithful end-to-end test (issue #196, ADR-0021): the golden path of a
/// portable backup — **respaldar -> base limpia -> restaurar -> todo
/// idéntico**. Follows the mold of `e2e_s1_rate_service_faithful_replay_test`
/// (#167) and `e2e_c3_reconciliation_routed_replay_test` (#156): real Drift
/// databases throughout (source *and* a completely separate, freshly-created
/// destination pair), no mocking.
///
/// Zero production changes: this composes existing machinery —
/// `CreateBackup` / `RestoreBackup` (`cuentaria_app`), the ledger factories
/// and cascade engine (`contabilidad`), and the rate series (`tasas`) — the
/// same way the app's own composition root wires them.
///
/// The scenario, seeded entirely by this test:
///   - Three accounts: USD (Efectivo), VES (BdV), and an **archived** EUR
///     account (Ahorros EUR) — each with its own color.
///   - Five user envelopes plus the four system ones: `Alquiler` (cascade
///     `fixed` target), `Fondo de Emergencia` (a **Cap** funding target,
///     cascade `fillToCap` target), `Ahorros` (a **GoalLine** funding
///     target, cascade `percentOfRemainder` target), `Varios` (cascade
///     `catchAll` target), `Mercado` (expense-only).
///   - A Cascade with one step of each of the four kinds.
///   - A Rate Series with observations from three sources (including a
///     `manual:*` one) across two calendar days plus a later one, so the
///     Resolution Chain has both same-day ties and a plain "latest day
///     wins" case to reproduce faithfully.
///   - Movements covering every archetype that exists today: Apertura
///     (x2 — USD, VES), Ingreso (x2 — one valued straight from the Rate
///     Series with no observed counterpart, ADR-0018; one routed out of a
///     Reconciliation), Gasto (USD), a cross-currency "transfer"
///     (`DisposalConversion`, VES -> USD), Distribución (the cascade),
///     Conciliación absorbida and Conciliación enrutada (ADR-0019), an
///     overdraft (ADR-0017), and a Reverso.
///
/// After backing up the source and restoring onto a completely fresh
/// database pair, the test asserts (per the ticket's acceptance criteria):
///   1. The Patrimonio snapshot matches to the cent — total, per account,
///      per envelope.
///   2. The Cascade restores with the same steps, order, and parameters.
///   3. Every event payload is byte-identical, character for character.
///   4. Funding Targets (`Cap`/`GoalLine`), colors, and archived state
///      survive.
///   5. The Resolution Chain picks the same rate *and* source for the same
///      date, before and after.
///   6. Restoring the same file a second time leaves every row count
///      unchanged.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:contabilidad/application/cascade/cascade.dart';
import 'package:contabilidad/application/cascade/cascade_step.dart';
import 'package:contabilidad/application/cascade/distribute_from_stage.dart';
import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/catalog/models/envelope_appearance.dart';
import 'package:contabilidad/application/catalog/models/funding_target.dart';
import 'package:contabilidad/application/ledger/factories/record_adjustment.dart';
import 'package:contabilidad/application/ledger/factories/record_distribution.dart';
import 'package:contabilidad/application/ledger/factories/record_income.dart';
import 'package:contabilidad/application/ledger/factories/record_opening.dart';
import 'package:contabilidad/application/ledger/factories/record_realization.dart';
import 'package:contabilidad/application/ledger/factories/record_reversal.dart';
import 'package:contabilidad/application/ledger/factories/record_usd_expense.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:contabilidad/domain/reconciliation/reconciliation_planner.dart';
import 'package:contabilidad/infrastructure/cascade/drift_cascade_repository.dart';
import 'package:contabilidad/infrastructure/catalog/drift_catalog_repository.dart';
import 'package:contabilidad/infrastructure/database/cuentaria_database.dart';
import 'package:contabilidad/infrastructure/database/drift_event_store.dart';
import 'package:contabilidad/infrastructure/database/drift_unit_of_work.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:cuentaria_app/features/backup/application/create_backup.dart';
import 'package:cuentaria_app/features/backup/application/restore_backup.dart';
import 'package:cuentaria_app/features/capture/application/quick_add_income_use_case.dart';
import 'package:cuentaria_app/features/reconciliation/application/mark_account_reconciled.dart';
import 'package:cuentaria_app/features/reconciliation/application/reconcile_use_case.dart';
import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:sqlite3/open.dart';
import 'package:tasas/application/rate_resolution_service.dart';
import 'package:tasas/domain/rate_observation.dart';
import 'package:tasas/infrastructure/drift/drift_rate_series.dart';
import 'package:tasas/infrastructure/drift/tasas_database.dart';

void _ensureSqlite3() {
  if (!Platform.isLinux) return;
  open.overrideForAll(() {
    try {
      return DynamicLibrary.open('libsqlite3.so');
    } catch (_) {
      // ignore: empty_catches
    }
    return DynamicLibrary.open('libsqlite3.so.0');
  });
}

// ---------------------------------------------------------------------------
// Catalog ids
// ---------------------------------------------------------------------------

final _usdId = AccountId('acc-usd');
final _vesId = AccountId('acc-ves');
final _eurId = AccountId('acc-eur');

final _rentId = EnvelopeId('env-alquiler');
final _emergencyId = EnvelopeId('env-emergencia');
final _savingsId = EnvelopeId('env-ahorros');
final _variosId = EnvelopeId('env-varios');
final _mercadoId = EnvelopeId('env-mercado');

// ---------------------------------------------------------------------------
// Session helper — wires one side (source or destination) over its own pair
// of Drift databases, exactly like the app's own composition root.
// ---------------------------------------------------------------------------

typedef _Session =
    ({
      DriftCatalogRepository catalog,
      DriftCascadeRepository cascadeRepo,
      DriftEventStore store,
      InMemoryLedgerProjections projections,
      DriftRateSeries rateSeries,
      RecordOpening recordOpening,
      RecordRealization recordRealization,
      RecordUsdExpense recordUsdExpense,
      RecordReversal recordReversal,
      DistributeFromStage distributor,
      QuickAddIncomeUseCase quickAddIncome,
      ReconcileUseCase reconcile,
      MarkAccountReconciled markReconciled,
    });

Future<_Session> _open(CuentariaDatabase db, TasasDatabase ratesDb) async {
  final catalog = DriftCatalogRepository(db);
  await catalog.hydrate();

  final cascadeRepo = DriftCascadeRepository(db);
  await cascadeRepo.hydrate();

  final store = DriftEventStore(db);
  final projections = InMemoryLedgerProjections();
  final bus = SyncEventBus();
  final validator = ReferentialIntegrityValidator(catalog);
  final recordTx = RecordTransaction(
    store: store,
    projections: projections,
    eventBus: bus,
    validator: validator,
  );
  final rateSeries = DriftRateSeries(ratesDb);
  final recordDistribution = RecordDistribution(
    record: recordTx,
    catalog: catalog,
  );

  return (
    catalog: catalog,
    cascadeRepo: cascadeRepo,
    store: store,
    projections: projections,
    rateSeries: rateSeries,
    recordOpening: RecordOpening(
      record: recordTx,
      catalog: catalog,
      projections: projections,
    ),
    recordRealization: RecordRealization(
      record: recordTx,
      catalog: catalog,
      projections: projections,
    ),
    recordUsdExpense: RecordUsdExpense(record: recordTx, catalog: catalog),
    recordReversal: RecordReversal(record: recordTx, store: store),
    distributor: DistributeFromStage(
      projections: projections,
      catalog: catalog,
      cascadeRepo: cascadeRepo,
      recordDistribution: recordDistribution,
    ),
    quickAddIncome: QuickAddIncomeUseCase(
      recordIncome: RecordIncome(record: recordTx, catalog: catalog),
      catalog: catalog,
      rateSeries: rateSeries,
    ),
    reconcile: ReconcileUseCase(
      recordAdjustment: RecordAdjustment(
        record: recordTx,
        projections: projections,
        catalog: catalog,
      ),
      catalog: catalog,
      projections: projections,
      rateSeries: rateSeries,
      markReconciled: MarkAccountReconciled(catalog: catalog),
    ),
    markReconciled: MarkAccountReconciled(catalog: catalog),
  );
}

/// Self-balancing invariant (ADR-0006): Σ usd[Account] == Σ usd[Envelope],
/// derived from the full catalog so no account/envelope can silently escape.
void _expectSelfBalancing(
  DriftCatalogRepository catalog,
  InMemoryLedgerProjections projections, {
  required String reason,
}) {
  final accountSum = catalog.accountIds
      .map((id) => projections.accountBalance(id).usd)
      .fold(0, (a, b) => a + b);
  final envelopeSum = catalog.envelopes
      .map((e) => projections.envelopeUsdBalance(e.id))
      .fold(0, (a, b) => a + b);
  expect(accountSum, equals(envelopeSum), reason: reason);
}

// ---------------------------------------------------------------------------
// Test
// ---------------------------------------------------------------------------

void main() {
  late CuentariaDatabase sourceLedgerDb;
  late TasasDatabase sourceRatesDb;
  late CuentariaDatabase destLedgerDb;
  late TasasDatabase destRatesDb;

  setUpAll(_ensureSqlite3);

  setUp(() {
    sourceLedgerDb = CuentariaDatabase(NativeDatabase.memory());
    sourceRatesDb = TasasDatabase(NativeDatabase.memory());
    destLedgerDb = CuentariaDatabase(NativeDatabase.memory());
    destRatesDb = TasasDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await sourceLedgerDb.close();
    await sourceRatesDb.close();
    await destLedgerDb.close();
    await destRatesDb.close();
  });

  test(
    'respaldar -> base limpia -> restaurar -> todo idéntico (PRD F4, golden path)',
    () async {
      final src = await _open(sourceLedgerDb, sourceRatesDb);

      // ---------------------------------------------------------------
      // Catalog: three accounts (USD, VES, an archived EUR), each with a
      // color; five user envelopes (two carrying Funding Targets).
      // ---------------------------------------------------------------
      await src.catalog.saveAccount(
        Account(
          id: _usdId,
          name: 'Efectivo',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.utc(2026, 1, 1),
          meta: const {'color': '#4CAF50'},
        ),
      );
      await src.catalog.saveAccount(
        Account(
          id: _vesId,
          name: 'BdV',
          nativeCurrency: CurrencyCode('VES'),
          isArchived: false,
          updatedAt: DateTime.utc(2026, 1, 1),
          meta: const {'color': '#2196F3'},
        ),
      );
      await src.catalog.saveAccount(
        Account(
          id: _eurId,
          name: 'Ahorros EUR',
          nativeCurrency: CurrencyCode('EUR'),
          isArchived: true,
          updatedAt: DateTime.utc(2026, 1, 1),
          meta: const {'color': '#9C27B0'},
        ),
      );

      await src.catalog.saveEnvelope(
        Envelope(
          id: _rentId,
          name: 'Alquiler',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.utc(2026, 1, 1),
        ).withAppearance(
          const EnvelopeAppearance(iconId: 'home', colorIndex: 2),
        ),
      );
      await src.catalog.saveEnvelope(
        Envelope(
          id: _emergencyId,
          name: 'Fondo de Emergencia',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.utc(2026, 1, 1),
        ).withTarget(const Cap(amountUsd: 50000)),
      );
      await src.catalog.saveEnvelope(
        Envelope(
          id: _savingsId,
          name: 'Ahorros',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.utc(2026, 1, 1),
        ).withTarget(
          GoalLine(amountUsd: 500000, dueDate: DateTime.utc(2026, 12, 31)),
        ),
      );
      await src.catalog.saveEnvelope(
        Envelope(
          id: _variosId,
          name: 'Varios',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await src.catalog.saveEnvelope(
        Envelope(
          id: _mercadoId,
          name: 'Mercado',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );

      final stageId = src.catalog.getSystemEnvelope(EnvelopeRole.stage);
      final openingId = src.catalog.getSystemEnvelope(EnvelopeRole.opening);
      final adjustmentsId = src.catalog.getSystemEnvelope(
        EnvelopeRole.adjustments,
      );

      // ---------------------------------------------------------------
      // Cascade: one step of each of the four kinds.
      // ---------------------------------------------------------------
      final cascade = Cascade(
        steps: [
          CascadeStep.fixed(envelopeId: _rentId, amountUsd: 20000),
          CascadeStep.fillToCap(envelopeId: _emergencyId),
          CascadeStep.percentOfRemainder(
            envelopeId: _savingsId,
            percent: Decimal.parse('0.5'),
            base: PercentBase.remainder,
          ),
          CascadeStep.catchAll(envelopeId: _variosId),
        ],
        updatedAt: DateTime.utc(2026, 1, 2),
      );
      await src.cascadeRepo.save(cascade);

      // ---------------------------------------------------------------
      // Rate Series: three sources across two calendar days, plus a
      // later one — same-day ties and plain "latest day wins" both
      // present in the series.
      // ---------------------------------------------------------------
      await src.rateSeries.append(
        RateObservation(
          currency: CurrencyCode('VES'),
          nativePerUsd: Decimal.parse('40.00'),
          observedAt: DateTime.utc(2026, 1, 1),
          source: 'binancep2p:ask',
        ),
      );
      await src.rateSeries.append(
        RateObservation(
          currency: CurrencyCode('VES'),
          nativePerUsd: Decimal.parse('41.50'),
          observedAt: DateTime.utc(2026, 1, 1),
          source: 'dolarapi:paralelo',
        ),
      );
      await src.rateSeries.append(
        RateObservation(
          currency: CurrencyCode('VES'),
          nativePerUsd: Decimal.parse('43.00'),
          observedAt: DateTime.utc(2026, 1, 8),
          source: 'binancep2p:ask',
        ),
      );
      await src.rateSeries.append(
        RateObservation(
          currency: CurrencyCode('VES'),
          nativePerUsd: Decimal.parse('44.00'),
          observedAt: DateTime.utc(2026, 1, 8),
          source: 'manual:paralelo',
        ),
      );
      await src.rateSeries.append(
        RateObservation(
          currency: CurrencyCode('VES'),
          nativePerUsd: Decimal.parse('46.00'),
          observedAt: DateTime.utc(2026, 1, 15),
          source: 'binancep2p:ask',
        ),
      );

      // ---------------------------------------------------------------
      // 1. Apertura x2 — USD straight, VES at an explicit rate.
      // ---------------------------------------------------------------
      await src.recordOpening.call(
        eventId: EventId('evt-open-usd'),
        deviceId: 'dev-test',
        accountId: _usdId,
        nativeAmount: Money(
          amount: BigInt.from(100000),
          currency: CurrencyCode('USD'),
        ),
        occurredAt: DomainTimestamp(DateTime.utc(2026, 1, 1)),
      );
      await src.recordOpening.call(
        eventId: EventId('evt-open-ves'),
        deviceId: 'dev-test',
        accountId: _vesId,
        nativeAmount: Money(
          amount: BigInt.from(400000),
          currency: CurrencyCode('VES'),
        ),
        rate: Decimal.parse('40.00'),
        occurredAt: DomainTimestamp(DateTime.utc(2026, 1, 1)),
      );
      expect(src.projections.accountBalance(_usdId).usd, equals(100000));
      expect(src.projections.accountBalance(_vesId).usd, equals(10000));
      expect(src.projections.envelopeUsdBalance(openingId), equals(110000));
      _expectSelfBalancing(
        src.catalog,
        src.projections,
        reason: 'after Apertura',
      );

      // ---------------------------------------------------------------
      // 2. Ingreso valued straight from the Rate Series, no observed
      // counterpart (ADR-0018) — resolves manual:paralelo @44.00, the
      // same-day tie-break winner over binancep2p:ask.
      // ---------------------------------------------------------------
      final incomeResolution = await RateResolutionService(src.rateSeries)(
        CurrencyCode('VES'),
        asOf: DateTime.utc(2026, 1, 8),
      );
      expect(incomeResolution!.source, equals('manual:paralelo'));
      expect(incomeResolution.nativePerUsd, equals(Decimal.parse('44.00')));

      await src.quickAddIncome.call(
        eventId: EventId('evt-income-ves'),
        deviceId: 'dev-test',
        accountId: _vesId,
        amount: Money(
          amount: BigInt.from(4400000),
          currency: CurrencyCode('VES'),
        ),
        source: 'Cliente',
        occurredAt: DomainTimestamp(DateTime.utc(2026, 1, 8)),
      );
      expect(src.projections.envelopeUsdBalance(stageId), equals(100000));
      _expectSelfBalancing(
        src.catalog,
        src.projections,
        reason: 'after Ingreso VES',
      );

      final incomeTx = (await src.store.queryLog()).singleWhere(
        (t) => t.metadata.eventId == EventId('evt-income-ves'),
      );
      final incomePosting = incomeTx.postings.singleWhere(
        (p) => p.rateRef != null,
      );
      expect(incomePosting.rateRef, contains('44.00'));

      // ---------------------------------------------------------------
      // 3. Distribución — the cascade over the full Stage balance.
      // ---------------------------------------------------------------
      await src.distributor.apply(
        eventId: EventId('evt-distribute'),
        deviceId: 'dev-test',
        amount: 100000,
      );
      expect(src.projections.envelopeUsdBalance(_rentId), equals(20000));
      expect(src.projections.envelopeUsdBalance(_emergencyId), equals(50000));
      expect(src.projections.envelopeUsdBalance(_savingsId), equals(15000));
      expect(src.projections.envelopeUsdBalance(_variosId), equals(15000));
      expect(src.projections.envelopeUsdBalance(stageId), equals(0));
      _expectSelfBalancing(
        src.catalog,
        src.projections,
        reason: 'after Distribución',
      );

      // ---------------------------------------------------------------
      // 4. Transferencia entre monedas — VES -> USD (DisposalConversion,
      // the only construct this domain permits for crossing currencies:
      // `RecordTransfer` rejects a currency change outright, ADR-0018 §3).
      // ---------------------------------------------------------------
      await src.recordRealization.disposalConversion(
        eventId: EventId('evt-convert'),
        deviceId: 'dev-test',
        sourceForeignAccountId: _vesId,
        destinationUsdAccountId: _usdId,
        nativeAmount: Money(
          amount: BigInt.from(2200000),
          currency: CurrencyCode('VES'),
        ),
        usdAmountReceived: Money(
          amount: BigInt.from(50000),
          currency: CurrencyCode('USD'),
        ),
        rateRef: '44.00 VES/USD',
        occurredAt: DomainTimestamp(DateTime.utc(2026, 1, 10)),
      );
      expect(
        src.projections.accountBalance(_vesId).native.amount,
        equals(BigInt.from(2600000)),
      );
      expect(src.projections.accountBalance(_usdId).usd, equals(150000));
      _expectSelfBalancing(
        src.catalog,
        src.projections,
        reason: 'after la transferencia entre monedas',
      );

      // ---------------------------------------------------------------
      // 5. Gasto — a plain USD expense.
      // ---------------------------------------------------------------
      await src.recordUsdExpense.call(
        eventId: EventId('evt-expense-usd'),
        deviceId: 'dev-test',
        accountId: _usdId,
        envelopeId: _mercadoId,
        amount: Money(amount: BigInt.from(5000), currency: CurrencyCode('USD')),
        occurredAt: DomainTimestamp(DateTime.utc(2026, 1, 11)),
      );
      expect(src.projections.accountBalance(_usdId).usd, equals(145000));
      expect(src.projections.envelopeUsdBalance(_mercadoId), equals(-5000));
      _expectSelfBalancing(src.catalog, src.projections, reason: 'after Gasto');

      // ---------------------------------------------------------------
      // 6. Sobregiro (ADR-0017) — a VES expense past the known balance.
      // ---------------------------------------------------------------
      await src.recordRealization.foreignCurrencyExpense(
        eventId: EventId('evt-expense-overdraft'),
        deviceId: 'dev-test',
        accountId: _vesId,
        destinationEnvelopeId: _mercadoId,
        nativeAmount: Money(
          amount: BigInt.from(5000000),
          currency: CurrencyCode('VES'),
        ),
        currentRate: Decimal.parse('45.00'),
        occurredAt: DomainTimestamp(DateTime.utc(2026, 1, 12)),
      );
      expect(
        src.projections.accountBalance(_vesId).native.amount,
        equals(BigInt.from(-2400000)),
        reason: 'Native balance goes negative — legal sobregiro (ADR-0017)',
      );
      expect(src.projections.envelopeUsdBalance(_mercadoId), equals(-116111));
      _expectSelfBalancing(
        src.catalog,
        src.projections,
        reason: 'after el sobregiro',
      );

      // ---------------------------------------------------------------
      // 7. Conciliación absorbida — a tiny delta, well under the $1.00
      // Tolerance.
      // ---------------------------------------------------------------
      final absorbOutcome = await src.reconcile.call(
        eventId: EventId('evt-reconcile-absorb'),
        deviceId: 'dev-test',
        accountId: _vesId,
        realNativeBalance: Money(
          amount: BigInt.from(-2399900),
          currency: CurrencyCode('VES'),
        ),
        occurredAt: DomainTimestamp(DateTime.utc(2026, 1, 13)),
      );
      expect(absorbOutcome, isA<Absorb>());
      expect(
        src.projections.accountBalance(_vesId).native.amount,
        equals(BigInt.from(-2399900)),
      );
      _expectSelfBalancing(
        src.catalog,
        src.projections,
        reason: 'after la Conciliación absorbida',
      );

      // ---------------------------------------------------------------
      // 8. Conciliación enrutada — a delta far over Tolerance routes to
      // Ingreso instead of absorbing.
      // ---------------------------------------------------------------
      final routeOutcome = await src.reconcile.call(
        eventId: EventId('evt-reconcile-route'),
        deviceId: 'dev-test',
        accountId: _vesId,
        realNativeBalance: Money(
          amount: BigInt.from(900000),
          currency: CurrencyCode('VES'),
        ),
      );
      expect(routeOutcome, isA<RouteToIncome>());
      final routed = routeOutcome as RouteToIncome;
      expect(
        src.projections.accountBalance(_vesId).native.amount,
        equals(BigInt.from(-2399900)),
        reason: 'RouteToIncome previews but does not post',
      );

      await src.quickAddIncome.call(
        eventId: EventId('evt-income-routed'),
        deviceId: 'dev-test',
        accountId: _vesId,
        amount: Money(
          amount: routed.deltaNative,
          currency: CurrencyCode('VES'),
        ),
        source: 'Cliente sin registrar',
        occurredAt: DomainTimestamp(DateTime.utc(2026, 1, 14)),
      );
      await src.markReconciled(_vesId, DateTime.utc(2026, 1, 14));
      expect(
        src.projections.accountBalance(_vesId).native.amount,
        equals(BigInt.from(900000)),
        reason: 'Native balance matches the declared real balance exactly',
      );
      _expectSelfBalancing(
        src.catalog,
        src.projections,
        reason: 'after la Conciliación enrutada',
      );

      // ---------------------------------------------------------------
      // 9. Reverso — undoes the plain USD expense.
      // ---------------------------------------------------------------
      await src.recordReversal.call(
        eventId: EventId('evt-reverse-usd-expense'),
        deviceId: 'dev-test',
        originalEventId: EventId('evt-expense-usd'),
        occurredAt: DomainTimestamp(DateTime.utc(2026, 1, 16)),
      );
      expect(src.projections.accountBalance(_usdId).usd, equals(150000));
      expect(src.projections.envelopeUsdBalance(_mercadoId), equals(-111111));
      expect(src.projections.envelopeUsdBalance(adjustmentsId), equals(2));
      _expectSelfBalancing(
        src.catalog,
        src.projections,
        reason: 'after el Reverso',
      );

      // =================================================================
      // Snapshot the source before backup.
      // =================================================================
      final sourceAccountSnapshot = {
        for (final id in src.catalog.accountIds)
          id: src.projections.accountBalance(id),
      };
      final sourceEnvelopeSnapshot = {
        for (final e in src.catalog.envelopes)
          e.id: src.projections.envelopeUsdBalance(e.id),
      };
      final sourceTotalUsd = sourceAccountSnapshot.values.fold(
        0,
        (a, b) => a + b.usd,
      );

      final resolutionDay1Before = await RateResolutionService(src.rateSeries)(
        CurrencyCode('VES'),
        asOf: DateTime.utc(2026, 1, 1),
      );
      final resolutionDay8Before = await RateResolutionService(src.rateSeries)(
        CurrencyCode('VES'),
        asOf: DateTime.utc(2026, 1, 8),
      );

      // =================================================================
      // Respaldar.
      // =================================================================
      final createBackup = CreateBackup(
        eventStore: src.store,
        catalog: src.catalog,
        cascade: src.cascadeRepo,
        rates: src.rateSeries,
        now: () => DateTime.utc(2026, 1, 20),
      );
      final backup = await createBackup();

      // =================================================================
      // Base limpia — a completely separate pair of Drift databases.
      // =================================================================
      final destCatalog = DriftCatalogRepository(destLedgerDb);
      await destCatalog.hydrate();
      final destCascadeRepo = DriftCascadeRepository(destLedgerDb);
      await destCascadeRepo.hydrate();
      final destStore = DriftEventStore(destLedgerDb);
      final destProjections = InMemoryLedgerProjections();
      final destEventBus = SyncEventBus();
      final destRateSeries = DriftRateSeries(destRatesDb);

      final restoreBackup = RestoreBackup(
        eventStore: destStore,
        catalog: destCatalog,
        cascade: destCascadeRepo,
        rates: destRateSeries,
        projections: destProjections,
        eventBus: destEventBus,
        unitOfWork: DriftUnitOfWork(
          destLedgerDb,
          onRollback: [destCatalog.hydrate, destCascadeRepo.hydrate],
        ),
      );

      // =================================================================
      // Restaurar.
      // =================================================================
      final restoreResult = await restoreBackup(backup.content);
      expect(restoreResult.eventsRestored, equals(backup.counts.event));

      // =================================================================
      // 1. Patrimonio: idéntico al centavo — total, por cuenta, por sobre.
      // =================================================================
      final destTotalUsd = destCatalog.accountIds
          .map((id) => destProjections.accountBalance(id).usd)
          .fold(0, (a, b) => a + b);
      expect(destTotalUsd, equals(sourceTotalUsd));

      for (final entry in sourceAccountSnapshot.entries) {
        final restored = destProjections.accountBalance(entry.key);
        expect(
          restored.native.amount,
          equals(entry.value.native.amount),
          reason: 'Restore: ${entry.key.value} native balance',
        );
        expect(
          restored.usd,
          equals(entry.value.usd),
          reason: 'Restore: ${entry.key.value} usd balance',
        );
      }
      for (final entry in sourceEnvelopeSnapshot.entries) {
        expect(
          destProjections.envelopeUsdBalance(entry.key),
          equals(entry.value),
          reason: 'Restore: ${entry.key.value} usd balance',
        );
      }
      _expectSelfBalancing(
        destCatalog,
        destProjections,
        reason: 'after restore',
      );

      // =================================================================
      // 2. Cascada: mismos pasos, mismo orden, mismos parámetros.
      // =================================================================
      final restoredCascade = await destCascadeRepo.load();
      expect(restoredCascade, isNotNull);
      expect(restoredCascade!.steps, hasLength(cascade.steps.length));
      for (var i = 0; i < cascade.steps.length; i++) {
        final original = cascade.steps[i];
        final copy = restoredCascade.steps[i];
        expect(
          copy.envelopeId,
          equals(original.envelopeId),
          reason: 'step $i envelopeId',
        );
        expect(
          copy.runtimeType,
          equals(original.runtimeType),
          reason: 'step $i type',
        );
        switch ((original, copy)) {
          case (FixedStep o, FixedStep c):
            expect(c.amountUsd, equals(o.amountUsd));
          case (PercentOfRemainderStep o, PercentOfRemainderStep c):
            expect(c.percent, equals(o.percent));
            expect(c.base, equals(o.base));
          default:
            break; // FillToCapStep / CatchAllStep carry no extra parameters
        }
      }

      // =================================================================
      // 3. Payloads de eventos: byte-idénticos.
      // =================================================================
      final sourcePayloads = await src.store.queryRawPayloads();
      final destPayloads = await destStore.queryRawPayloads();
      expect(destPayloads, hasLength(sourcePayloads.length));
      expect(destPayloads.toSet(), equals(sourcePayloads.toSet()));

      // =================================================================
      // 4. Metas de Financiamiento, colores, y estado archivado.
      // =================================================================
      expect(destCatalog.getAccount(_usdId)?.colorHex, equals('#4CAF50'));
      expect(destCatalog.getAccount(_vesId)?.colorHex, equals('#2196F3'));
      final restoredEur = destCatalog.getAccount(_eurId);
      expect(restoredEur?.colorHex, equals('#9C27B0'));
      expect(restoredEur?.isArchived, isTrue);

      expect(
        destCatalog.getEnvelope(_emergencyId)?.target,
        equals(const Cap(amountUsd: 50000)),
      );
      expect(
        destCatalog.getEnvelope(_savingsId)?.target,
        equals(
          GoalLine(amountUsd: 500000, dueDate: DateTime.utc(2026, 12, 31)),
        ),
      );
      expect(
        destCatalog.getEnvelope(_rentId)?.appearance,
        equals(const EnvelopeAppearance(iconId: 'home', colorIndex: 2)),
      );

      // =================================================================
      // 5. Cadena de Resolución: misma tasa, misma fuente, misma fecha.
      // =================================================================
      final resolutionDay1After = await RateResolutionService(destRateSeries)(
        CurrencyCode('VES'),
        asOf: DateTime.utc(2026, 1, 1),
      );
      expect(resolutionDay1After!.source, equals(resolutionDay1Before!.source));
      expect(
        resolutionDay1After.nativePerUsd,
        equals(resolutionDay1Before.nativePerUsd),
      );
      expect(resolutionDay1After.source, equals('binancep2p:ask'));

      final resolutionDay8After = await RateResolutionService(destRateSeries)(
        CurrencyCode('VES'),
        asOf: DateTime.utc(2026, 1, 8),
      );
      expect(resolutionDay8After!.source, equals(resolutionDay8Before!.source));
      expect(
        resolutionDay8After.nativePerUsd,
        equals(resolutionDay8Before.nativePerUsd),
      );
      expect(resolutionDay8After.source, equals('manual:paralelo'));

      // =================================================================
      // 6. Restaurar una segunda vez no cambia ningún número ni fila.
      // =================================================================
      final eventCountBefore = (await destStore.queryLog()).length;
      final accountCountBefore = destCatalog.accounts.length;
      final envelopeCountBefore = destCatalog.envelopes.length;
      final rateCountBefore = (await destRateSeries.allObservations()).length;

      final secondRestore = await restoreBackup(backup.content);

      expect(
        secondRestore.eventsRestored,
        equals(restoreResult.eventsRestored),
      );
      expect((await destStore.queryLog()).length, equals(eventCountBefore));
      expect(destCatalog.accounts.length, equals(accountCountBefore));
      expect(destCatalog.envelopes.length, equals(envelopeCountBefore));
      expect(
        (await destRateSeries.allObservations()).length,
        equals(rateCountBefore),
      );
      for (final entry in sourceAccountSnapshot.entries) {
        expect(
          destProjections.accountBalance(entry.key).usd,
          equals(entry.value.usd),
          reason: 'Second restore: ${entry.key.value} unchanged',
        );
      }
      _expectSelfBalancing(
        destCatalog,
        destProjections,
        reason: 'after the second restore',
      );
    },
  );
}
