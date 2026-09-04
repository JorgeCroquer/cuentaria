/// F3 faithful end-to-end test (issue #227, ADR-0023): two complete app
/// containers — `NativeDatabase.memory()` and distinct `device_id`s each —
/// sharing one `InMemoryCloudFolder`, with `CloudCopyTriggers` (F3.5, issue
/// #224) actually wired and firing, and a fake clock throughout (no
/// `DateTime.now()`). Follows the mold of `e2e_f4_backup_portable_faithful_test`
/// (#196) and `cloud_copy_use_case_test.dart` (#222): real Drift databases,
/// real `CreateBackup`/`RestoreBackup`/`CloudCopyUseCase`, no mocking.
///
/// The path (all seeded by this test):
///   - A creates Efectivo (USD) and Banesco (VES), records a $1.000,00
///     Ingreso to Efectivo, a 2-step Cascade (fixed Alquiler + catchAll
///     Varios), distributes it, then a 4.000 Bs Gasto from Banesco at rate
///     40 (freezes $100,00 USD) into Varios.
///   - A's trigger pushes to the shared cloud folder.
///   - B, empty, connects: its first sync pulls A's file. Patrimonio and
///     Cascade end up identical to A's, to the cent.
///   - B records a $25,00 Gasto from Efectivo, **dated before A's last
///     movement** — its trigger pushes to the cloud.
///   - A comes back to the foreground (`onResume`, ADR-0023 §4): its sync
///     pulls B's file. Efectivo's balance drops by $25,00, and A's balance
///     *as of B's expense date* — computed before and after this sync —
///     changes retroactively (ADR-0023 §consequence, accepted).
///   - Three more sync rounds in both directions change no number: same
///     event counts, byte-for-byte identical `PatrimonioSnapshot`s.
///
/// Zero production changes: this composes existing machinery only.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:backup/backup.dart';
import 'package:backup/infrastructure/in_memory_cloud_folder.dart';
import 'package:contabilidad/application/cascade/cascade.dart';
import 'package:contabilidad/application/cascade/cascade_step.dart';
import 'package:contabilidad/application/cascade/distribute_from_stage.dart';
import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/catalog/models/funding_target.dart';
import 'package:contabilidad/application/ledger/factories/record_distribution.dart';
import 'package:contabilidad/application/ledger/factories/record_income.dart';
import 'package:contabilidad/application/ledger/factories/record_realization.dart';
import 'package:contabilidad/application/ledger/factories/record_usd_expense.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:contabilidad/domain/ports/log_filters.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/infrastructure/cascade/drift_cascade_repository.dart';
import 'package:contabilidad/infrastructure/catalog/drift_catalog_repository.dart';
import 'package:contabilidad/infrastructure/database/cloud_copy_status_store.dart';
import 'package:contabilidad/infrastructure/database/cuentaria_database.dart';
import 'package:contabilidad/infrastructure/database/drift_event_store.dart';
import 'package:contabilidad/infrastructure/database/drift_unit_of_work.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:cuentaria_app/features/backup/application/create_backup.dart';
import 'package:cuentaria_app/features/backup/application/restore_backup.dart';
import 'package:cuentaria_app/features/cloud_copy/application/cloud_copy_triggers.dart';
import 'package:cuentaria_app/features/cloud_copy/application/cloud_copy_use_case.dart';
import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrimonio/patrimonio.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:sqlite3/open.dart';
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
// Catalog ids — shared identifiers, since Cloud Copy syncs the same
// entities across devices by ID (ADR-0005: cross-references are by ID).
// ---------------------------------------------------------------------------

final _usdId = AccountId('acc-usd');
final _vesId = AccountId('acc-ves');
final _rentId = EnvelopeId('env-alquiler');
final _variosId = EnvelopeId('env-varios');

/// The fake clock (ticket #227: "reloj falso") — every `now()` this test
/// wires in returns this fixed instant, so backup headers and CloudCopy
/// status stamps are deterministic.
DateTime _fakeNow() => DateTime.utc(2026, 1, 20);

/// Lets a `CloudCopyTriggers`-fired sync (debounce is [Duration.zero] in
/// this test) actually run: the debounce `Timer` and this wait are both
/// macrotasks, registered in that order, so by the time this one fires the
/// triggered sync's whole microtask chain (pull, restore, push) has already
/// completed. Without this, asserting right after a trigger call would pass
/// even if the trigger never fired anything.
Future<void> _waitForDebounce() =>
    Future<void>.delayed(const Duration(milliseconds: 1));

// ---------------------------------------------------------------------------
// Device — one full app container: its own pair of Drift databases, the
// ledger/cascade machinery, and a real CloudCopyUseCase + CloudCopyTriggers
// (F3.5, #224) wired to its own EventBus, exactly like the composition root.
// ---------------------------------------------------------------------------

class _Device {
  final CuentariaDatabase ledgerDb;
  final TasasDatabase ratesDb;
  final DriftCatalogRepository catalog;
  final DriftCascadeRepository cascadeRepo;
  final DriftEventStore store;
  final InMemoryLedgerProjections projections;
  final DriftRateSeries rateSeries;
  final RecordIncome recordIncome;
  final RecordUsdExpense recordUsdExpense;
  final RecordRealization recordRealization;
  final DistributeFromStage distributor;
  final CloudCopyUseCase cloudCopy;
  final CloudCopyTriggers triggers;

  _Device({
    required this.ledgerDb,
    required this.ratesDb,
    required this.catalog,
    required this.cascadeRepo,
    required this.store,
    required this.projections,
    required this.rateSeries,
    required this.recordIncome,
    required this.recordUsdExpense,
    required this.recordRealization,
    required this.distributor,
    required this.cloudCopy,
    required this.triggers,
  });

  Future<void> close() async {
    triggers.dispose();
    await ledgerDb.close();
    await ratesDb.close();
  }
}

Future<_Device> _openDevice(String deviceId, CloudFolder folder) async {
  final ledgerDb = CuentariaDatabase(NativeDatabase.memory());
  final ratesDb = TasasDatabase(NativeDatabase.memory());

  final catalog = DriftCatalogRepository(ledgerDb);
  await catalog.hydrate();
  final cascadeRepo = DriftCascadeRepository(ledgerDb);
  await cascadeRepo.hydrate();
  final store = DriftEventStore(ledgerDb);
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
  final statusStore = CloudCopyStatusStore(ledgerDb);

  final createBackup = CreateBackup(
    eventStore: store,
    catalog: catalog,
    cascade: cascadeRepo,
    rates: rateSeries,
    now: _fakeNow,
  );
  final restoreBackup = RestoreBackup(
    eventStore: store,
    catalog: catalog,
    cascade: cascadeRepo,
    rates: rateSeries,
    projections: projections,
    eventBus: bus,
    unitOfWork: DriftUnitOfWork(
      ledgerDb,
      onRollback: [catalog.hydrate, cascadeRepo.hydrate],
    ),
  );
  final cloudCopy = CloudCopyUseCase(
    createBackup: createBackup,
    restoreBackup: restoreBackup,
    cloudFolder: folder,
    statusStore: statusStore,
    deviceId: deviceId,
    now: _fakeNow,
  );

  return _Device(
    ledgerDb: ledgerDb,
    ratesDb: ratesDb,
    catalog: catalog,
    cascadeRepo: cascadeRepo,
    store: store,
    projections: projections,
    rateSeries: rateSeries,
    recordIncome: RecordIncome(record: recordTx, catalog: catalog),
    recordUsdExpense: RecordUsdExpense(record: recordTx, catalog: catalog),
    recordRealization: RecordRealization(
      record: recordTx,
      catalog: catalog,
      projections: projections,
    ),
    distributor: DistributeFromStage(
      projections: projections,
      catalog: catalog,
      cascadeRepo: cascadeRepo,
      recordDistribution: RecordDistribution(
        record: recordTx,
        catalog: catalog,
      ),
    ),
    cloudCopy: cloudCopy,
    triggers: CloudCopyTriggers(
      sync: cloudCopy.sync,
      eventBus: bus,
      debounce: Duration.zero,
    ),
  );
}

/// Self-balancing invariant (ADR-0006): Σ usd[Account] == Σ usd[Envelope].
void _expectSelfBalancing(_Device d, {required String reason}) {
  final accountSum = d.catalog.accountIds
      .map((id) => d.projections.accountBalance(id).usd)
      .fold(0, (a, b) => a + b);
  final envelopeSum = d.catalog.envelopes
      .map((e) => d.projections.envelopeUsdBalance(e.id))
      .fold(0, (a, b) => a + b);
  expect(accountSum, equals(envelopeSum), reason: reason);
}

/// This device's `usd`-basis balance of [accountId], counting only
/// transactions dated on or before [asOf] — reuses `LogFilters` (the same
/// account/date index `queryLog` already exposes) rather than hand-rolling a
/// second replay.
Future<int> _accountUsdBalanceAsOf(
  _Device d,
  AccountId accountId,
  DateTime asOf,
) async {
  final transactions = await d.store.queryLog(
    filters: LogFilters(account: accountId, to: DomainTimestamp(asOf)),
  );
  var total = 0;
  for (final tx in transactions) {
    for (final posting in tx.postings) {
      final target = posting.target;
      if (target is AccountTarget && target.accountId == accountId) {
        total += posting.amountUsd;
      }
    }
  }
  return total;
}

// ---------------------------------------------------------------------------
// Patrimonio — the same mapping `patrimonioSnapshotProvider` does (app-layer
// wiring from contabilidad's catalog/projections into patrimonio's own
// views, ADR-0005), reproduced here without Riverpod since this is a pure
// e2e over the domain/application layers only.
// ---------------------------------------------------------------------------

const _patrimonioEngine = PatrimonioEngine();

Future<PatrimonioSnapshot> _patrimonio(_Device d) async {
  final accounts = [
    for (final account in d.catalog.accounts)
      AccountView(
        id: account.id,
        currency: account.nativeCurrency,
        nativeMinorAmount:
            d.projections.accountBalance(account.id).native.amount,
        realCostUsdCents: d.projections.accountBalance(account.id).usd,
        isArchived: account.isArchived,
      ),
  ];

  final envelopes = [
    for (final envelope in d.catalog.envelopes)
      EnvelopeView(
        id: envelope.id,
        name: envelope.name,
        role: _mapRole(envelope.role),
        balanceUsd: d.projections.envelopeUsdBalance(envelope.id),
        target: _mapTarget(envelope.target),
        iconId: envelope.appearance.iconId,
        colorIndex: envelope.appearance.colorIndex,
      ),
  ];

  return _patrimonioEngine(accounts, const {}, envelopes, _fakeNow());
}

EnvelopeRoleView _mapRole(EnvelopeRole role) => switch (role) {
  EnvelopeRole.none => EnvelopeRoleView.user,
  EnvelopeRole.stage => EnvelopeRoleView.stage,
  EnvelopeRole.differential => EnvelopeRoleView.differential,
  EnvelopeRole.adjustments => EnvelopeRoleView.adjustments,
  EnvelopeRole.opening => EnvelopeRoleView.opening,
};

FundingTargetView _mapTarget(FundingTarget target) => switch (target) {
  NoTarget() => const NoTargetView(),
  Cap(:final amountUsd) => CapView(amountUsd: amountUsd),
  GoalLine(:final amountUsd, :final dueDate) => GoalLineView(
    amountUsd: amountUsd,
    dueDate: dueDate,
  ),
};

/// Order-insensitive copy, so comparing two devices' snapshots doesn't
/// depend on incidental Map/row iteration order surviving a restore.
PatrimonioSnapshot _normalized(PatrimonioSnapshot s) {
  final groups = [...s.accountGroups]
    ..sort((a, b) => a.currency.value.compareTo(b.currency.value));
  final envelopes = [...s.envelopes]
    ..sort((a, b) => a.id.value.compareTo(b.id.value));
  return PatrimonioSnapshot(
    realCostUsdCents: s.realCostUsdCents,
    todayValueUsdCents: s.todayValueUsdCents,
    unrealizedPnlUsdCents: s.unrealizedPnlUsdCents,
    bcvReferenceUsdCents: s.bcvReferenceUsdCents,
    hasMissingRate: s.hasMissingRate,
    accountGroups: groups,
    envelopes: envelopes,
  );
}

// ---------------------------------------------------------------------------
// Test
// ---------------------------------------------------------------------------

void main() {
  setUpAll(_ensureSqlite3);

  test(
    'A crea y distribuye, B conecta e iguala, B gasta hacia atrás, A sincroniza '
    'y ve el gasto — tres rondas más no cambian nada (PRD F3, golden path)',
    () async {
      final folder = InMemoryCloudFolder();
      final a = await _openDevice('device-a', folder);

      // ---------------------------------------------------------------
      // A: catalog + a 2-step cascade (fixed Alquiler + catchAll Varios).
      // ---------------------------------------------------------------
      await a.catalog.saveAccount(
        Account(
          id: _usdId,
          name: 'Efectivo',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await a.catalog.saveAccount(
        Account(
          id: _vesId,
          name: 'Banesco',
          nativeCurrency: CurrencyCode('VES'),
          isArchived: false,
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await a.catalog.saveEnvelope(
        Envelope(
          id: _rentId,
          name: 'Alquiler',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await a.catalog.saveEnvelope(
        Envelope(
          id: _variosId,
          name: 'Varios',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await a.cascadeRepo.save(
        Cascade(
          steps: [
            CascadeStep.fixed(envelopeId: _rentId, amountUsd: 20000),
            CascadeStep.catchAll(envelopeId: _variosId),
          ],
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );

      final stageId = a.catalog.getSystemEnvelope(EnvelopeRole.stage);

      // ---------------------------------------------------------------
      // Ingreso $1.000,00 a Efectivo.
      // ---------------------------------------------------------------
      await a.recordIncome.call(
        eventId: EventId('evt-income'),
        deviceId: 'device-a',
        accountId: _usdId,
        amount: Money(
          amount: BigInt.from(100000),
          currency: CurrencyCode('USD'),
        ),
        source: 'Cliente',
        occurredAt: DomainTimestamp(DateTime.utc(2026, 1, 2)),
      );
      expect(a.projections.accountBalance(_usdId).usd, equals(100000));
      expect(a.projections.envelopeUsdBalance(stageId), equals(100000));

      // ---------------------------------------------------------------
      // Distribución — la cascada de 2 pasos.
      // ---------------------------------------------------------------
      await a.distributor.apply(
        eventId: EventId('evt-distribute'),
        deviceId: 'device-a',
        amount: 100000,
      );
      expect(a.projections.envelopeUsdBalance(_rentId), equals(20000));
      expect(a.projections.envelopeUsdBalance(_variosId), equals(80000));
      expect(a.projections.envelopeUsdBalance(stageId), equals(0));

      // ---------------------------------------------------------------
      // Gasto 4.000 Bs desde Banesco a tasa 40 → congela $100,00 USD.
      // ---------------------------------------------------------------
      await a.recordRealization.foreignCurrencyExpense(
        eventId: EventId('evt-expense-ves'),
        deviceId: 'device-a',
        accountId: _vesId,
        destinationEnvelopeId: _variosId,
        nativeAmount: Money(
          amount: BigInt.from(400000),
          currency: CurrencyCode('VES'),
        ),
        currentRate: Decimal.parse('40.00'),
        occurredAt: DomainTimestamp(DateTime.utc(2026, 1, 3)),
      );
      expect(
        a.projections.accountBalance(_vesId).native.amount,
        equals(BigInt.from(-400000)),
      );
      expect(a.projections.accountBalance(_vesId).usd, equals(-10000));
      expect(a.projections.envelopeUsdBalance(_variosId), equals(70000));
      _expectSelfBalancing(a, reason: 'after A\'s setup');

      // ---------------------------------------------------------------
      // Disparador (F3.5, #224): la copia sube a la nube compartida.
      // ---------------------------------------------------------------
      a.triggers.start();
      await _waitForDebounce();
      expect(await folder.list(), equals(['device-a.ndjson']));

      // ---------------------------------------------------------------
      // B vacío conecta: su primer sync (disparado por start()) baja el
      // archivo de A.
      // ---------------------------------------------------------------
      final b = await _openDevice('device-b', folder);
      b.triggers.start();
      await _waitForDebounce();

      for (final id in a.catalog.accountIds) {
        expect(
          b.projections.accountBalance(id).usd,
          equals(a.projections.accountBalance(id).usd),
          reason: 'account ${id.value} usd balance, to the cent',
        );
        expect(
          b.projections.accountBalance(id).native.amount,
          equals(a.projections.accountBalance(id).native.amount),
          reason: 'account ${id.value} native balance, to the cent',
        );
      }
      for (final envelope in a.catalog.envelopes) {
        expect(
          b.projections.envelopeUsdBalance(envelope.id),
          equals(a.projections.envelopeUsdBalance(envelope.id)),
          reason: 'envelope ${envelope.id.value} usd balance, to the cent',
        );
      }
      expect(
        _normalized(await _patrimonio(b)),
        equals(_normalized(await _patrimonio(a))),
      );

      final aCascade = await a.cascadeRepo.load();
      final bCascade = await b.cascadeRepo.load();
      expect(bCascade, isNotNull);
      expect(bCascade!.steps, hasLength(2));
      expect(bCascade.steps, hasLength(aCascade!.steps.length));
      for (var i = 0; i < aCascade.steps.length; i++) {
        expect(
          bCascade.steps[i].envelopeId,
          equals(aCascade.steps[i].envelopeId),
        );
        expect(
          bCascade.steps[i].runtimeType,
          equals(aCascade.steps[i].runtimeType),
        );
      }

      // ---------------------------------------------------------------
      // Assert de "saldo cambia hacia atrás" (ADR-0023 §consequence),
      // parte 1: antes de que A vea el gasto de B, el saldo de A del
      // 1/1 — la fecha en la que B va a fechar su gasto — es cero.
      // ---------------------------------------------------------------
      final bExpenseDate = DateTime.utc(2026, 1, 1);
      final aBalanceBeforeMerge = await _accountUsdBalanceAsOf(
        a,
        _usdId,
        bExpenseDate,
      );
      expect(aBalanceBeforeMerge, equals(0));

      // ---------------------------------------------------------------
      // B registra un gasto de $25,00, fechado *antes* del último
      // movimiento de A (1/3) — de hecho, antes de todos los de A.
      // ---------------------------------------------------------------
      await b.recordUsdExpense.call(
        eventId: EventId('evt-b-expense'),
        deviceId: 'device-b',
        accountId: _usdId,
        envelopeId: _variosId,
        amount: Money(amount: BigInt.from(2500), currency: CurrencyCode('USD')),
        occurredAt: DomainTimestamp(bExpenseDate),
      );

      // Disparador en B (evento Transaction del gasto, debounced): sube el
      // archivo a la nube.
      await _waitForDebounce();

      // ---------------------------------------------------------------
      // A vuelve a primer plano (ADR-0023 §4, onResume): su sync baja el
      // archivo de B y lo mezcla de forma idempotente.
      // ---------------------------------------------------------------
      a.triggers.onResume();
      await _waitForDebounce();

      expect(
        a.projections.accountBalance(_usdId).usd,
        equals(97500),
        reason: 'Efectivo baja de \$1.000,00 a \$975,00',
      );
      expect(a.projections.envelopeUsdBalance(_variosId), equals(67500));
      _expectSelfBalancing(a, reason: 'after A ve el gasto de B');

      // ---------------------------------------------------------------
      // Assert de "saldo cambia hacia atrás", parte 2: el mismo saldo
      // histórico de A al 1/1 ahora refleja el gasto de B.
      // ---------------------------------------------------------------
      final aBalanceAfterMerge = await _accountUsdBalanceAsOf(
        a,
        _usdId,
        bExpenseDate,
      );
      expect(
        aBalanceAfterMerge,
        equals(-2500),
        reason: 'El saldo del 1/1 cambió hacia atrás al mezclar el gasto de B',
      );
      expect(aBalanceAfterMerge, isNot(equals(aBalanceBeforeMerge)));

      // ---------------------------------------------------------------
      // Tres rondas más de sync en ambos: ningún número cambia.
      // ---------------------------------------------------------------
      final aEventCount = (await a.store.queryLog()).length;
      final bEventCount = (await b.store.queryLog()).length;
      final aPatrimonioBefore = _normalized(await _patrimonio(a));
      final bPatrimonioBefore = _normalized(await _patrimonio(b));

      for (var round = 0; round < 3; round++) {
        await a.cloudCopy.sync();
        await b.cloudCopy.sync();
      }

      expect((await a.store.queryLog()).length, equals(aEventCount));
      expect((await b.store.queryLog()).length, equals(bEventCount));
      expect(_normalized(await _patrimonio(a)), equals(aPatrimonioBefore));
      expect(_normalized(await _patrimonio(b)), equals(bPatrimonioBefore));
      _expectSelfBalancing(a, reason: 'after 3 extra sync rounds (A)');
      _expectSelfBalancing(b, reason: 'after 3 extra sync rounds (B)');

      await a.close();
      await b.close();
    },
  );
}
