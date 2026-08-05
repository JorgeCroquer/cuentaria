/// C3 faithful end-to-end test (issue #151, ADR-0019): the golden path that
/// motivated all of C3 — sobregiro → conciliar → enrutado a Ingreso → fecha
/// anterior → valoración con la tasa de esa fecha — with replay of the event
/// log as the spine, following the mold of `e2e_faithful_replay_test` (C1)
/// and `e2e_c2_faithful_replay_test` (C2).
///
/// Lives in `cuentaria_app`, not `contabilidad`, because the routed
/// reconciliation orchestration ([ReconcileUseCase], [QuickAddIncomeUseCase])
/// composes `contabilidad` with `tasas`' [RateSeries], which `contabilidad`
/// may not import (ADR-0005) — same reason those classes themselves live
/// here. Uses the real Drift databases for both contexts (no mocking),
/// wired exactly as the app's own providers wire them
/// (`composition_root.dart`, `tasas_providers.dart`,
/// `reconciliation_providers.dart`).
///
/// Golden path, narrated in USD cents (VES 40.00/USD until 2026-01-10, then
/// 50.00/USD):
///   1. Open BdV (VES) with 4 000.00 Bs @ 40.00 -> $100.00 (native 400000).
///   2. Small downward absorption (Reconciliation, delta = -$0.01, under the
///      $1.00 Tolerance) -> Adjustment. Native 399960, usd 9999.
///   3. A 5 000.00 Bs grocery expense exceeds the known balance -> sobregiro
///      (ADR-0017): native goes negative (-100040), usd -2501.
///   4. Reconciliation declares the real balance positive (9 000.00 Bs) ->
///      delta = 10 000.40 Bs, far over Tolerance -> routes to Income.
///   5. The user says it actually happened 2026-01-05 — between the two Rate
///      Observations — so the routed Income freezes with the 2026-01-01
///      observation (40.00), NOT the latest one (50.00 @ 2026-01-10).
///   6. Native lands exactly on the declared 900000; money is in Stage.
/// Self-balancing (Σ usd[Account] == Σ usd[Envelope]) is checked after every
/// transaction, not just at the end. Replay reconstructs both dimensions:
/// the ledger (via [RebuildProjections]) and the rate series (a fresh
/// [DriftRateSeries] over the same, still-open database).
library;

import 'dart:ffi';
import 'dart:io';

import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/ledger/factories/record_adjustment.dart';
import 'package:contabilidad/application/ledger/factories/record_income.dart';
import 'package:contabilidad/application/ledger/factories/record_opening.dart';
import 'package:contabilidad/application/ledger/factories/record_realization.dart';
import 'package:contabilidad/application/ledger/rebuild_projections.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:contabilidad/domain/reconciliation/reconciliation_planner.dart';
import 'package:contabilidad/infrastructure/catalog/drift_catalog_repository.dart';
import 'package:contabilidad/infrastructure/database/cuentaria_database.dart';
import 'package:contabilidad/infrastructure/database/drift_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:cuentaria_app/features/capture/application/quick_add_income_use_case.dart';
import 'package:cuentaria_app/features/reconciliation/application/mark_account_reconciled.dart';
import 'package:cuentaria_app/features/reconciliation/application/reconcile_use_case.dart';
import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:sqlite3/open.dart';
import 'package:tasas/domain/rate_observation.dart';
import 'package:tasas/infrastructure/drift/drift_rate_series.dart';
import 'package:tasas/infrastructure/drift/tasas_database.dart';

const _paraleloSource = 'manual:paralelo';

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
// Session helpers
// ---------------------------------------------------------------------------

typedef _Session =
    ({
      DriftCatalogRepository catalog,
      DriftEventStore store,
      InMemoryLedgerProjections projections,
      DriftRateSeries rateSeries,
      RecordOpening recordOpening,
      RecordRealization recordRealization,
      ReconcileUseCase reconcile,
      QuickAddIncomeUseCase quickAddIncome,
      MarkAccountReconciled markReconciled,
    });

Future<_Session> _open(CuentariaDatabase db, TasasDatabase ratesDb) async {
  final catalog = DriftCatalogRepository(db);
  await catalog.hydrate();

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
  final markReconciled = MarkAccountReconciled(catalog: catalog);

  return (
    catalog: catalog,
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
    reconcile: ReconcileUseCase(
      recordAdjustment: RecordAdjustment(
        record: recordTx,
        projections: projections,
        catalog: catalog,
      ),
      catalog: catalog,
      projections: projections,
      rateSeries: rateSeries,
      markReconciled: markReconciled,
    ),
    quickAddIncome: QuickAddIncomeUseCase(
      recordIncome: RecordIncome(record: recordTx, catalog: catalog),
      catalog: catalog,
      rateSeries: rateSeries,
    ),
    markReconciled: markReconciled,
  );
}

/// Replays the ledger dimension: fresh projections rebuilt from the event
/// log over the same (still-open) database.
Future<InMemoryLedgerProjections> _replayLedger(CuentariaDatabase db) async {
  final p = InMemoryLedgerProjections();
  await RebuildProjections(
    store: DriftEventStore(db),
    projections: p,
  ).execute();
  return p;
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
  late CuentariaDatabase ledgerDb;
  late TasasDatabase ratesDb;

  setUpAll(_ensureSqlite3);

  setUp(() {
    ledgerDb = CuentariaDatabase(NativeDatabase.memory());
    ratesDb = TasasDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await ledgerDb.close();
    await ratesDb.close();
  });

  test('sobregiro -> conciliar -> enrutado a Ingreso -> fecha anterior -> '
      'valorado con la tasa de esa fecha, no la última; replay fiel', () async {
    final s = await _open(ledgerDb, ratesDb);

    final vesId = AccountId('acc-ves');
    await s.catalog.saveAccount(
      Account(
        id: vesId,
        name: 'BdV',
        nativeCurrency: CurrencyCode('VES'),
        isArchived: false,
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );
    final groceriesId = EnvelopeId('env-groceries');
    await s.catalog.saveEnvelope(
      Envelope(
        id: groceriesId,
        name: 'Mercado',
        role: EnvelopeRole.none,
        isArchived: false,
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );

    final stageId = s.catalog.getSystemEnvelope(EnvelopeRole.stage);
    final openingId = s.catalog.getSystemEnvelope(EnvelopeRole.opening);
    final adjustmentsId = s.catalog.getSystemEnvelope(EnvelopeRole.adjustments);

    // -- Setup: two Rate Observations, tasa1 old and tasa2 latest -------
    final tasa1 = RateObservation(
      currency: CurrencyCode('VES'),
      nativePerUsd: Decimal.parse('40.00'),
      observedAt: DateTime.utc(2026, 1, 1),
      source: _paraleloSource,
    );
    final tasa2 = RateObservation(
      currency: CurrencyCode('VES'),
      nativePerUsd: Decimal.parse('50.00'),
      observedAt: DateTime.utc(2026, 1, 10),
      source: _paraleloSource,
    );
    await s.rateSeries.append(tasa1);
    await s.rateSeries.append(tasa2);

    // ---------------------------------------------------------------
    // 1. Opening: 4 000.00 Bs @ 40.00 -> $100.00
    // ---------------------------------------------------------------
    await s.recordOpening.call(
      eventId: EventId('evt-opening'),
      deviceId: 'dev-test',
      accountId: vesId,
      nativeAmount: Money(
        amount: BigInt.from(400000),
        currency: CurrencyCode('VES'),
      ),
      rate: Decimal.parse('40.00'),
      occurredAt: DomainTimestamp(DateTime.utc(2026, 1, 1)),
    );

    expect(s.projections.accountBalance(vesId).usd, equals(10000));
    expect(s.projections.envelopeUsdBalance(openingId), equals(10000));
    _expectSelfBalancing(s.catalog, s.projections, reason: 'after Opening');

    // ---------------------------------------------------------------
    // 2. Small downward absorption (below the $1.00 Tolerance): the
    //    declared balance is 3 999.60 Bs vs the 4 000.00 projected, a
    //    -40 native delta -> -$0.01, absorbed against Ajustes.
    // ---------------------------------------------------------------
    final outcome1 = await s.reconcile.call(
      eventId: EventId('evt-reconcile-absorb'),
      deviceId: 'dev-test',
      accountId: vesId,
      realNativeBalance: Money(
        amount: BigInt.from(399960),
        currency: CurrencyCode('VES'),
      ),
      occurredAt: DomainTimestamp(DateTime.utc(2026, 1, 2)),
    );

    expect(
      outcome1,
      isA<Absorb>(),
      reason: 'Delta of -\$0.01 is well under the \$1.00 Tolerance',
    );
    expect((outcome1 as Absorb).deltaUsd, equals(-1));
    expect(
      s.projections.accountBalance(vesId).native.amount,
      equals(BigInt.from(399960)),
    );
    expect(s.projections.accountBalance(vesId).usd, equals(9999));
    expect(s.projections.envelopeUsdBalance(adjustmentsId), equals(-1));
    _expectSelfBalancing(
      s.catalog,
      s.projections,
      reason: 'after absorbed Adjustment',
    );

    // ---------------------------------------------------------------
    // 3. Overdraft: a 5 000.00 Bs grocery expense exceeds the known
    //    399960 native balance -> negative native balance (ADR-0017).
    // ---------------------------------------------------------------
    await s.recordRealization.foreignCurrencyExpense(
      eventId: EventId('evt-expense-overdraft'),
      deviceId: 'dev-test',
      accountId: vesId,
      destinationEnvelopeId: groceriesId,
      nativeAmount: Money(
        amount: BigInt.from(500000),
        currency: CurrencyCode('VES'),
      ),
      currentRate: Decimal.parse('40.00'),
      occurredAt: DomainTimestamp(DateTime.utc(2026, 1, 3)),
    );

    final overdrawn = s.projections.accountBalance(vesId);
    expect(
      overdrawn.native.amount,
      equals(BigInt.from(-100040)),
      reason: 'Native balance goes negative — legal sobregiro (ADR-0017)',
    );
    expect(overdrawn.usd, equals(-2501));
    _expectSelfBalancing(
      s.catalog,
      s.projections,
      reason: 'after the overdrawing expense',
    );

    // ---------------------------------------------------------------
    // 4. Reconciliation: the real balance is positive (a client paid
    //    into BdV without it being registered). The delta is far over
    //    Tolerance -> routes to Income instead of absorbing.
    // ---------------------------------------------------------------
    final outcome2 = await s.reconcile.call(
      eventId: EventId('evt-reconcile-route'),
      deviceId: 'dev-test',
      accountId: vesId,
      realNativeBalance: Money(
        amount: BigInt.from(900000),
        currency: CurrencyCode('VES'),
      ),
    );

    expect(outcome2, isA<RouteToIncome>());
    final routed = outcome2 as RouteToIncome;
    expect(routed.deltaNative, equals(BigInt.from(1000040)));
    // Sized against the LATEST rate (tasa2, 50.00) — this is a routing
    // preview, distinct from the historical rate the posted Income will
    // actually freeze with in the next step.
    expect(routed.suggestedUsd, equals(20001));

    // Nothing posted yet for a routed outcome: balance is unchanged and
    // still negative.
    expect(
      s.projections.accountBalance(vesId).native.amount,
      equals(BigInt.from(-100040)),
    );
    _expectSelfBalancing(
      s.catalog,
      s.projections,
      reason: 'RouteToIncome previews but does not post',
    );

    // ---------------------------------------------------------------
    // 5. The user says the money actually arrived on 2026-01-05 — a
    //    date for which tasa1 (2026-01-01) is the applicable
    //    observation, NOT tasa2 (2026-01-10, the latest overall).
    // ---------------------------------------------------------------
    final asOfObservation = await s.rateSeries.latestFor(
      CurrencyCode('VES'),
      source: _paraleloSource,
      asOf: DateTime.utc(2026, 1, 5),
    );
    expect(asOfObservation, equals(tasa1));
    expect(
      asOfObservation,
      isNot(equals(tasa2)),
      reason:
          'Historical lookup must resolve to the 2026-01-01 observation, '
          'explicitly not the latest one from 2026-01-10',
    );

    await s.quickAddIncome.call(
      eventId: EventId('evt-income-routed'),
      deviceId: 'dev-test',
      accountId: vesId,
      amount: Money(amount: routed.deltaNative, currency: CurrencyCode('VES')),
      source: 'Cliente sin registrar',
      occurredAt: DomainTimestamp(DateTime.utc(2026, 1, 5)),
    );
    await s.markReconciled(vesId, DateTime.utc(2026, 1, 5));

    // The frozen Income posting used tasa1's rate (40.00), NOT tasa2's
    // (50.00): 1 000 040 / 40.00 = 25 001, not 1 000 040 / 50.00 = 20 001.
    final incomeTx = (await s.store.queryLog()).singleWhere(
      (t) => t.metadata.eventId == EventId('evt-income-routed'),
    );
    final accountPosting = incomeTx.postings.firstWhere(
      (p) => p.amountUsd != 0 && p.rateRef != null,
    );
    expect(accountPosting.amountUsd, equals(25001));
    expect(accountPosting.rateRef, contains('40.00'));
    expect(
      accountPosting.rateRef,
      isNot(contains('50.00')),
      reason: 'Explicitly not the latest rate in the series',
    );

    // ---------------------------------------------------------------
    // 6. Post conditions: native balance matches the declared value,
    //    the money is in Stage, and the invariant holds.
    // ---------------------------------------------------------------
    final settled = s.projections.accountBalance(vesId);
    expect(
      settled.native.amount,
      equals(BigInt.from(900000)),
      reason: 'Native balance matches the declared real balance exactly',
    );
    expect(settled.usd, equals(22500));
    expect(
      s.projections.envelopeUsdBalance(stageId),
      equals(25001),
      reason: 'The routed Income lands in Stage',
    );
    _expectSelfBalancing(
      s.catalog,
      s.projections,
      reason: 'after the routed, historically-rated Income',
    );

    final account = s.catalog.getAccount(vesId)!;
    expect(
      account.lastReconciledAt,
      isNotNull,
      reason: 'A routed Income that posts stamps lastReconciledAt too',
    );

    // ---------------------------------------------------------------
    // Snapshot before replay
    // ---------------------------------------------------------------
    final accountSnapshot = s.projections.accountBalance(vesId);
    final envelopeSnapshot = {
      for (final e in s.catalog.envelopes)
        e.id: s.projections.envelopeUsdBalance(e.id),
    };

    // ---------------------------------------------------------------
    // Replay both dimensions: the ledger (fresh projections rebuilt
    // from the event log) and the rate series (fresh reader over the
    // same, still-open tasas database).
    // ---------------------------------------------------------------
    final catalog2 = DriftCatalogRepository(ledgerDb);
    await catalog2.hydrate();
    final projections2 = await _replayLedger(ledgerDb);
    final rateSeries2 = DriftRateSeries(ratesDb);

    final replayedAccount = projections2.accountBalance(vesId);
    expect(
      replayedAccount.native.amount,
      equals(accountSnapshot.native.amount),
      reason: 'Replay: native balance matches pre-replay snapshot',
    );
    expect(
      replayedAccount.usd,
      equals(accountSnapshot.usd),
      reason: 'Replay: usd balance matches pre-replay snapshot',
    );
    for (final entry in envelopeSnapshot.entries) {
      expect(
        projections2.envelopeUsdBalance(entry.key),
        equals(entry.value),
        reason: 'Replay: ${entry.key.value} matches pre-replay snapshot',
      );
    }
    _expectSelfBalancing(catalog2, projections2, reason: 'after replay');

    final replayedAsOf = await rateSeries2.latestFor(
      CurrencyCode('VES'),
      source: _paraleloSource,
      asOf: DateTime.utc(2026, 1, 5),
    );
    expect(
      replayedAsOf,
      equals(tasa1),
      reason: 'Replay: historical rate lookup still resolves to tasa1',
    );
    expect(replayedAsOf, isNot(equals(tasa2)));
  });
}
