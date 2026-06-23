/// C2 faithful end-to-end test: define cascade → income(s) → distribute →
/// verify per-envelope/Stage balances with exact numbers → replay from log →
/// confirm identical balances.
///
/// Two narrated scenarios (issue #62 + ADR-0015):
///
/// 1. **Lean month** ($700 income; plan wants $500 rent + $300 mercado + $200
///    savings). Rent fills ($500), Mercado gets $200 (clamped), Savings gets
///    $0 (remaining = 0). Nothing negative. Stage = $0 (no catch-all residue
///    here because we use explicit fixed steps and stage is drained by the
///    amounts that fit).
///    Precise numbers: income=700, rent=500 (full), mercado=200 (partial,
///    clamped from 300), savings=0 (clamped from 200), stage=0.
///
/// 2. **Mercado accumulative over 2 months** (fixed $300 step to Mercado;
///    catch-all to Savings). Month-1: income $1 000 → Mercado +300, Savings
///    +700. Month-1 user only spends $200 from Mercado (explicit USD expense).
///    Mercado ends month at $100 surplus. Month-2: income $1 000 again →
///    cascade runs → Mercado gets another $300 (fixed, NOT fillToCap), so
///    Mercado = 100 + 300 = $400 (cushion). Proves fixed ACCUMULATES.
///
/// Replay parity: after each scenario the log is replayed into a fresh
/// InMemoryLedgerProjections and balances must match exactly.
///
/// Uses the real Drift database (DriftCatalogRepository + DriftEventStore +
/// DriftCascadeRepository) — no mocking. Prior art: e2e_faithful_replay_test.
library;

import 'package:contabilidad/application/cascade/cascade.dart';
import 'package:contabilidad/application/cascade/cascade_step.dart';
import 'package:contabilidad/application/cascade/distribute_from_stage.dart';
import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/ledger/factories/record_distribution.dart';
import 'package:contabilidad/application/ledger/factories/record_income.dart';
import 'package:contabilidad/application/ledger/factories/record_usd_expense.dart';
import 'package:contabilidad/application/ledger/rebuild_projections.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:contabilidad/infrastructure/cascade/drift_cascade_repository.dart';
import 'package:contabilidad/infrastructure/catalog/drift_catalog_repository.dart';
import 'package:contabilidad/infrastructure/database/cuentaria_database.dart';
import 'package:contabilidad/infrastructure/database/drift_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:event_bus/event_bus.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:test/test.dart';

import '../../infrastructure/catalog/test_helpers.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

typedef _Ctx =
    ({
      DriftCatalogRepository catalog,
      DriftCascadeRepository cascadeRepo,
      DriftEventStore store,
      InMemoryLedgerProjections projections,
      RecordIncome recordIncome,
      RecordUsdExpense recordUsdExpense,
      DistributeFromStage distributor,
    });

Future<_Ctx> _open(CuentariaDatabase db) async {
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
  final recordDist = RecordDistribution(record: recordTx, catalog: catalog);

  return (
    catalog: catalog,
    cascadeRepo: cascadeRepo,
    store: store,
    projections: projections,
    recordIncome: RecordIncome(record: recordTx, catalog: catalog),
    recordUsdExpense: RecordUsdExpense(record: recordTx, catalog: catalog),
    distributor: DistributeFromStage(
      projections: projections,
      catalog: catalog,
      cascadeRepo: cascadeRepo,
      recordDistribution: recordDist,
    ),
  );
}

/// Replays the event log from [db] into a fresh InMemoryLedgerProjections.
Future<InMemoryLedgerProjections> _replay(CuentariaDatabase db) async {
  final p = InMemoryLedgerProjections();
  await RebuildProjections(
    store: DriftEventStore(db),
    projections: p,
  ).execute();
  return p;
}

AccountId _addAccount(DriftCatalogRepository cat, String id) {
  final accountId = AccountId(id);
  cat.saveAccount(
    Account(
      id: accountId,
      name: id,
      nativeCurrency: CurrencyCode('USD'),
      isArchived: false,
      updatedAt: DateTime.utc(2026, 1, 1),
    ),
  );
  return accountId;
}

EnvelopeId _addEnvelope(DriftCatalogRepository cat, String id) {
  final envId = EnvelopeId(id);
  cat.saveEnvelope(
    Envelope(
      id: envId,
      name: id,
      role: EnvelopeRole.none,
      isArchived: false,
      updatedAt: DateTime.utc(2026, 1, 1),
    ),
  );
  return envId;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late CuentariaDatabase db;

  setUpAll(ensureSqlite3);

  setUp(() {
    db = openTestDb();
  });

  tearDown(() => db.close());

  // =========================================================================
  // Scenario 1 — Lean month
  //
  // Plan (fixed steps, no catch-all):
  //   Step 1: Rent   fixed $500  (essential, top priority)
  //   Step 2: Mercado fixed $300  (middle)
  //   Step 3: Savings fixed $200  (bottom, will get $0)
  //
  // Income = $700 (lean month).
  //
  // Engine walk:
  //   remaining = 700
  //   Step 1 Rent:    calc=500, give=min(500,700)=500  → remaining=200
  //   Step 2 Mercado: calc=300, give=min(300,200)=200  → remaining=0
  //   Step 3 Savings: calc=200, give=min(200,0)=0      → remaining=0
  //
  // Expected:
  //   Rent    = 500   (fully funded)
  //   Mercado = 200   (partially funded — clamped)
  //   Savings = 0     (got nothing)
  //   Stage   = 0     (all income distributed, no residue)
  //   No envelope negative.
  // =========================================================================
  group('C2 e2e faithful — lean month', () {
    test(
      'essential steps fill first; savings gets \$0; nothing negative; replay parity',
      () async {
        final ctx = await _open(db);

        // -- Catalog --
        final accId = _addAccount(ctx.catalog, 'acc-lean');
        final envRent = _addEnvelope(ctx.catalog, 'env-rent');
        final envMercado = _addEnvelope(ctx.catalog, 'env-mercado');
        final envSavings = _addEnvelope(ctx.catalog, 'env-savings');
        final stageId = ctx.catalog.getSystemEnvelope(EnvelopeRole.stage);

        // -- Define + save cascade (real Drift DB) --
        await ctx.cascadeRepo.save(
          Cascade(
            steps: [
              CascadeStep.fixed(envelopeId: envRent, amountUsd: 500),
              CascadeStep.fixed(envelopeId: envMercado, amountUsd: 300),
              CascadeStep.fixed(envelopeId: envSavings, amountUsd: 200),
            ],
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );

        // -- Record lean-month income ($700 → Stage) --
        await ctx.recordIncome(
          eventId: EventId('evt-lean-income'),
          deviceId: 'dev',
          accountId: accId,
          amount: Money(
            amount: BigInt.from(700),
            currency: CurrencyCode('USD'),
          ),
          source: 'lean client payment',
          occurredAt: DomainTimestamp(DateTime.utc(2026, 1, 5)),
        );

        // Confirm Stage received the income
        expect(ctx.projections.envelopeUsdBalance(stageId), equals(700));

        // -- Distribute via real orchestrator --
        await ctx.distributor.apply(
          eventId: EventId('evt-lean-dist'),
          deviceId: 'dev',
        );

        // -- Assert exact balances --
        expect(
          ctx.projections.envelopeUsdBalance(envRent),
          equals(500),
          reason: 'Rent: fully funded (top priority)',
        );
        expect(
          ctx.projections.envelopeUsdBalance(envMercado),
          equals(200),
          reason: 'Mercado: partially funded (clamped from 300 to 200)',
        );
        expect(
          ctx.projections.envelopeUsdBalance(envSavings),
          equals(0),
          reason: 'Savings: gets \$0 (remaining exhausted above)',
        );
        expect(
          ctx.projections.envelopeUsdBalance(stageId),
          equals(0),
          reason: 'Stage: zero (all income consumed)',
        );
        // No envelope negative (invariant)
        expect(
          ctx.projections.envelopeUsdBalance(envRent),
          greaterThanOrEqualTo(0),
        );
        expect(
          ctx.projections.envelopeUsdBalance(envMercado),
          greaterThanOrEqualTo(0),
        );
        expect(
          ctx.projections.envelopeUsdBalance(envSavings),
          greaterThanOrEqualTo(0),
        );
        expect(
          ctx.projections.envelopeUsdBalance(stageId),
          greaterThanOrEqualTo(0),
        );

        // -- Replay parity: replay log → same balances --
        final replayed = await _replay(db);
        expect(
          replayed.envelopeUsdBalance(envRent),
          equals(500),
          reason: 'Replay: Rent=500',
        );
        expect(
          replayed.envelopeUsdBalance(envMercado),
          equals(200),
          reason: 'Replay: Mercado=200',
        );
        expect(
          replayed.envelopeUsdBalance(envSavings),
          equals(0),
          reason: 'Replay: Savings=0',
        );
        expect(
          replayed.envelopeUsdBalance(stageId),
          equals(0),
          reason: 'Replay: Stage=0',
        );
        expect(
          replayed.accountBalance(accId).usd,
          equals(700),
          reason: 'Replay: account balance unchanged',
        );
      },
    );
  });

  // =========================================================================
  // Scenario 2 — Mercado accumulative over 2 months
  //
  // Plan:
  //   Step 1: Mercado fixed $300  (accumulates — NOT fillToCap)
  //   Step 2: Savings catch-all   (gets the rest)
  //
  // Month 1:
  //   Income = $1 000 → Stage = 1 000
  //   Distribute: Mercado +300, Savings +700; Stage = 0
  //   User spends $200 from Mercado (USD expense): Mercado = 100
  //
  // Month 2:
  //   Income = $1 000 → Stage = 1 000
  //   Distribute: Mercado +300 (fixed, always 300 regardless of current balance)
  //             Savings +700
  //   Mercado = 100 + 300 = 400  ← cushion grows! fixed ACCUMULATES.
  //   Savings = 700 + 700 = 1 400
  //   Stage   = 0
  //   Account total = 2 000 (2 incomes) − 200 (expense) = 1 800
  //
  // Replay parity: log replayed from Drift → same balances.
  // =========================================================================
  group('C2 e2e faithful — Mercado accumulative (2 months)', () {
    test(
      'fixed \$300 step accumulates cushion over 2 months; NOT fillToCap; replay parity',
      () async {
        final ctx = await _open(db);

        // -- Catalog --
        final accM1 = _addAccount(ctx.catalog, 'acc-m1');
        final accM2 = _addAccount(ctx.catalog, 'acc-m2');
        final envMercado = _addEnvelope(ctx.catalog, 'env-mercado');
        final envSavings = _addEnvelope(ctx.catalog, 'env-savings');
        final stageId = ctx.catalog.getSystemEnvelope(EnvelopeRole.stage);

        // -- Define cascade once (fixed $300 to Mercado, catch-all to Savings) --
        await ctx.cascadeRepo.save(
          Cascade(
            steps: [
              CascadeStep.fixed(envelopeId: envMercado, amountUsd: 300),
              CascadeStep.catchAll(envelopeId: envSavings),
            ],
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );

        // -- Month 1: income $1 000 --
        await ctx.recordIncome(
          eventId: EventId('evt-m1-income'),
          deviceId: 'dev',
          accountId: accM1,
          amount: Money(
            amount: BigInt.from(1000),
            currency: CurrencyCode('USD'),
          ),
          source: 'month-1 client',
          occurredAt: DomainTimestamp(DateTime.utc(2026, 1, 5)),
        );

        expect(ctx.projections.envelopeUsdBalance(stageId), equals(1000));

        await ctx.distributor.apply(
          eventId: EventId('evt-m1-dist'),
          deviceId: 'dev',
          amount: 1000,
        );

        // After month-1 distribution
        expect(
          ctx.projections.envelopeUsdBalance(envMercado),
          equals(300),
          reason: 'Month-1: Mercado=300 after distribution',
        );
        expect(
          ctx.projections.envelopeUsdBalance(envSavings),
          equals(700),
          reason: 'Month-1: Savings=700 after distribution',
        );
        expect(
          ctx.projections.envelopeUsdBalance(stageId),
          equals(0),
          reason: 'Month-1: Stage fully drained',
        );

        // Month-1: user spends $200 from Mercado (only partial spend — surplus stays)
        await ctx.recordUsdExpense(
          eventId: EventId('evt-m1-expense'),
          deviceId: 'dev',
          accountId: accM1,
          envelopeId: envMercado,
          amount: Money(
            amount: BigInt.from(200),
            currency: CurrencyCode('USD'),
          ),
          occurredAt: DomainTimestamp(DateTime.utc(2026, 1, 20)),
        );

        // Mercado surplus stays: 300 − 200 = 100
        expect(
          ctx.projections.envelopeUsdBalance(envMercado),
          equals(100),
          reason: 'Month-1 after spend: Mercado=100 (surplus stays)',
        );

        // -- Month 2: income $1 000 --
        await ctx.recordIncome(
          eventId: EventId('evt-m2-income'),
          deviceId: 'dev',
          accountId: accM2,
          amount: Money(
            amount: BigInt.from(1000),
            currency: CurrencyCode('USD'),
          ),
          source: 'month-2 client',
          occurredAt: DomainTimestamp(DateTime.utc(2026, 2, 5)),
        );

        expect(ctx.projections.envelopeUsdBalance(stageId), equals(1000));

        await ctx.distributor.apply(
          eventId: EventId('evt-m2-dist'),
          deviceId: 'dev',
          amount: 1000,
        );

        // -- Assert month-2 final balances (exact numbers) --
        // Mercado: fixed always gives $300 regardless of current balance
        // 100 (surplus from month-1) + 300 (month-2 fixed) = 400
        expect(
          ctx.projections.envelopeUsdBalance(envMercado),
          equals(400),
          reason:
              'Mercado=400: fixed accumulates (100 surplus + 300 month-2). '
              'Would be 300 if this were fillToCap(cap=300) — proves accumulation.',
        );
        // Savings: 700 + 700 = 1 400
        expect(
          ctx.projections.envelopeUsdBalance(envSavings),
          equals(1400),
          reason: 'Savings=1400: 700 month-1 + 700 month-2',
        );
        expect(
          ctx.projections.envelopeUsdBalance(stageId),
          equals(0),
          reason: 'Stage=0: fully drained both months',
        );

        // Account total: 1000 + 1000 − 200 = 1800
        final totalAccountUsd =
            ctx.projections.accountBalance(accM1).usd +
            ctx.projections.accountBalance(accM2).usd;
        expect(
          totalAccountUsd,
          equals(1800),
          reason: 'Accounts: 2×income(1000) − expense(200) = 1800',
        );

        // Self-balancing invariant: Σ accounts == Σ envelopes
        final envelopeSum =
            ctx.projections.envelopeUsdBalance(envMercado) +
            ctx.projections.envelopeUsdBalance(envSavings) +
            ctx.projections.envelopeUsdBalance(stageId) +
            ctx.projections.envelopeUsdBalance(
              ctx.catalog.getSystemEnvelope(EnvelopeRole.differential),
            ) +
            ctx.projections.envelopeUsdBalance(
              ctx.catalog.getSystemEnvelope(EnvelopeRole.opening),
            ) +
            ctx.projections.envelopeUsdBalance(
              ctx.catalog.getSystemEnvelope(EnvelopeRole.adjustments),
            );
        expect(
          totalAccountUsd,
          equals(envelopeSum),
          reason: 'Self-balancing invariant: Σ accounts == Σ envelopes',
        );

        // -- Replay parity: reopen DB session → replay log → same balances --
        final replayed = await _replay(db);

        expect(
          replayed.envelopeUsdBalance(envMercado),
          equals(400),
          reason: 'Replay parity: Mercado=400',
        );
        expect(
          replayed.envelopeUsdBalance(envSavings),
          equals(1400),
          reason: 'Replay parity: Savings=1400',
        );
        expect(
          replayed.envelopeUsdBalance(stageId),
          equals(0),
          reason: 'Replay parity: Stage=0',
        );
        expect(
          replayed.accountBalance(accM1).usd +
              replayed.accountBalance(accM2).usd,
          equals(1800),
          reason: 'Replay parity: accounts=1800',
        );
      },
    );
  });
}
