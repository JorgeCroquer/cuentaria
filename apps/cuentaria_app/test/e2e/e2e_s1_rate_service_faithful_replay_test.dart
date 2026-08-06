/// S1 faithful end-to-end test (issue #167, ADR-0020): the golden path of
/// the Rate Service, valuing a single VES account's expenses against a
/// **published rate series served from a fixture** — zero network calls.
/// Follows the mold of `e2e_c3_reconciliation_routed_replay_test.dart`
/// (#151): real Drift databases for both contexts, no mocking, replay of
/// the event log as the spine.
///
/// Test-only slice: composes existing machinery (`SyncRateSeriesUseCase`,
/// `RateResolutionService`, `QuickAddExpenseUseCase`, `RecordRealization`)
/// with zero production changes — if it needed one, that would be a sign
/// slice 3 (#165) or slice 4 (#166) fell short, per the ticket.
///
/// Seven acceptance criteria, narrated over a single VES account, 10 000.00
/// Bs (native 1 000 000) expensed each time so every posting's usd delta is
/// a pure function of the day's resolved rate:
///   1. Fresh install: the synced published series already answers the VES
///      rate before any expense exists — the app doesn't ask.
///   2. 2026-08-04: `binancep2p:ask` (845.88) prices the expense
///      ($11.82), not `dolarapi:paralelo` (834.370612, $11.99).
///   3. 2026-08-05: the primary source is silent that day; only
///      `dolarapi:paralelo` (836.50) is available and it prices the
///      expense — nothing breaks, nothing is left unvalued.
///   4. 2026-08-06: a manual entry (840.00) beats a same-day automatic
///      reading (838.00) by source priority. 2026-08-07: with a fresh
///      automatic reading (847.00) and no new manual entry, the automatic
///      takes over alone — the prior day's manual never leaks forward.
///   5. Offline, no new sync: an expense recorded "today" (2026-08-09,
///      two days after the last observation) still posts, frozen with
///      that stale 2026-08-07 rate.
///   6. An expense backdated to 2026-08-04 freezes with that day's
///      `binancep2p:ask` (845.88), not the latest observation in the
///      series (2026-08-07's 847.00) — ADR-0019 §5's promise, now for
///      automatic sources too.
///   7. Replay reconstructs both dimensions (ledger + rate series) from
///      the still-open databases; balances and historical resolutions
///      match exactly.
/// Self-balancing (Σ usd[Account] == Σ usd[Envelope]) is checked after
/// every transaction. A repeated sync of the same fixture is asserted to
/// add nothing and move no balance.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/ledger/factories/record_realization.dart';
import 'package:contabilidad/application/ledger/factories/record_usd_expense.dart';
import 'package:contabilidad/application/ledger/rebuild_projections.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:contabilidad/infrastructure/catalog/drift_catalog_repository.dart';
import 'package:contabilidad/infrastructure/database/cuentaria_database.dart';
import 'package:contabilidad/infrastructure/database/drift_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:cuentaria_app/features/capture/application/quick_add_expense_use_case.dart';
import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:sqlite3/open.dart';
import 'package:tasas/application/rate_resolution_service.dart';
import 'package:tasas/application/sync_rate_series_use_case.dart';
import 'package:tasas/domain/rate_observation.dart';
import 'package:tasas/infrastructure/drift/drift_rate_series.dart';
import 'package:tasas/infrastructure/drift/tasas_database.dart';
import 'package:tasas/infrastructure/in_memory/in_memory_rate_feed.dart';

final _vesId = AccountId('acc-ves');
final _groceriesId = EnvelopeId('env-mercado');

final _dayA = DateTime.utc(2026, 8, 4);
final _dayB = DateTime.utc(2026, 8, 5);
final _dayManual = DateTime.utc(2026, 8, 6);
final _dayAutoTakesOver = DateTime.utc(2026, 8, 7);
final _offlineToday = DateTime.utc(2026, 8, 9);

final _tenThousandBs = Money(
  amount: BigInt.from(1000000),
  currency: CurrencyCode('VES'),
);

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
      QuickAddExpenseUseCase quickAddExpense,
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

  return (
    catalog: catalog,
    store: store,
    projections: projections,
    rateSeries: rateSeries,
    quickAddExpense: QuickAddExpenseUseCase(
      recordUsdExpense: RecordUsdExpense(record: recordTx, catalog: catalog),
      recordRealization: RecordRealization(
        record: recordTx,
        catalog: catalog,
        projections: projections,
      ),
      catalog: catalog,
      rateSeries: rateSeries,
    ),
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

/// The rateRef-carrying posting of a foreign-currency expense is always the
/// destination envelope posting (`RecordRealization._performDisposal`),
/// valued at the resolved rate regardless of the account's own cost basis.
Future<void> _expectExpenseFrozeAt({
  required DriftEventStore store,
  required EventId eventId,
  required int expectedUsdCents,
  required String expectedRateText,
  required String notExpectedRateText,
}) async {
  final tx = (await store.queryLog()).singleWhere(
    (t) => t.metadata.eventId == eventId,
  );
  final destPosting = tx.postings.singleWhere((p) => p.rateRef != null);
  expect(destPosting.amountUsd, equals(-expectedUsdCents));
  expect(destPosting.rateRef, contains(expectedRateText));
  expect(destPosting.rateRef, isNot(contains(notExpectedRateText)));
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

  test('camino dorado del Servicio de Tasas: serie publicada desde fixture, '
      'cero red, replay fiel', () async {
    final s = await _open(ledgerDb, ratesDb);

    await s.catalog.saveAccount(
      Account(
        id: _vesId,
        name: 'Binance',
        nativeCurrency: CurrencyCode('VES'),
        isArchived: false,
        updatedAt: _dayA,
      ),
    );
    await s.catalog.saveEnvelope(
      Envelope(
        id: _groceriesId,
        name: 'Mercado',
        role: EnvelopeRole.none,
        isArchived: false,
        updatedAt: _dayA,
      ),
    );

    // ---------------------------------------------------------------
    // 1. Fresh install: sync the published series from a fixture (no
    // network) and confirm the app already knows the VES rate before a
    // single expense exists.
    // ---------------------------------------------------------------
    final fixture =
        File('test/fixtures/s1_published_rates.ndjson').readAsStringSync();
    final sync = SyncRateSeriesUseCase(InMemoryRateFeed(fixture), s.rateSeries);
    await sync.sync();

    final freshInstall = await RateResolutionService(s.rateSeries)(
      CurrencyCode('VES'),
      asOf: _dayA,
    );
    expect(
      freshInstall,
      isNotNull,
      reason: 'the app already knows the rate — it does not ask',
    );
    expect(freshInstall!.source, equals('binancep2p:ask'));
    expect(freshInstall.nativePerUsd, equals(Decimal.parse('845.88')));

    // Repeated sync of the same fixture: no duplicate rows, no balance
    // movement.
    final rowsAfterFirstSync =
        await ratesDb.select(ratesDb.rateObservations).get();
    await sync.sync();
    final rowsAfterSecondSync =
        await ratesDb.select(ratesDb.rateObservations).get();
    expect(
      rowsAfterSecondSync.length,
      equals(rowsAfterFirstSync.length),
      reason: 'a repeated sync of the same published series adds nothing',
    );
    expect(
      s.projections.accountBalance(_vesId).usd,
      equals(0),
      reason: 'syncing rates never moves a balance',
    );

    // ---------------------------------------------------------------
    // 2. Published rate wins: the expense freezes at binancep2p:ask
    // (845.88 -> $11.82), not dolarapi:paralelo (834.370612 -> $11.99).
    // ---------------------------------------------------------------
    await s.quickAddExpense.call(
      eventId: EventId('evt-day-a'),
      deviceId: 'dev-test',
      accountId: _vesId,
      envelopeId: _groceriesId,
      amount: _tenThousandBs,
      occurredAt: DomainTimestamp(_dayA),
    );
    _expectSelfBalancing(
      s.catalog,
      s.projections,
      reason: 'after Day A expense',
    );
    await _expectExpenseFrozeAt(
      store: s.store,
      eventId: EventId('evt-day-a'),
      expectedUsdCents: 1182,
      expectedRateText: '845.88',
      notExpectedRateText: '834.37',
    );
    expect(s.projections.envelopeUsdBalance(_groceriesId), equals(-1182));

    // ---------------------------------------------------------------
    // 3. Primary source falls silent: only dolarapi:paralelo (836.50)
    // is observed that day, and the valuation uses it — declared via
    // the resolution, nothing left unvalued.
    // ---------------------------------------------------------------
    final dayBResolution = await RateResolutionService(s.rateSeries)(
      CurrencyCode('VES'),
      asOf: _dayB,
    );
    expect(dayBResolution!.source, equals('dolarapi:paralelo'));
    expect(dayBResolution.nativePerUsd, equals(Decimal.parse('836.50')));

    await s.quickAddExpense.call(
      eventId: EventId('evt-day-b'),
      deviceId: 'dev-test',
      accountId: _vesId,
      envelopeId: _groceriesId,
      amount: _tenThousandBs,
      occurredAt: DomainTimestamp(_dayB),
    );
    _expectSelfBalancing(
      s.catalog,
      s.projections,
      reason: 'after Day B expense',
    );
    await _expectExpenseFrozeAt(
      store: s.store,
      eventId: EventId('evt-day-b'),
      expectedUsdCents: 1195,
      expectedRateText: '836.50',
      notExpectedRateText: '845.88',
    );
    expect(
      s.projections.envelopeUsdBalance(_groceriesId),
      equals(-1182 - 1195),
    );

    // ---------------------------------------------------------------
    // 4a. A manual entry (840.00) beats a same-day automatic reading
    // (838.00, from the fixture) by source priority — manual rules
    // only the day it is typed.
    // ---------------------------------------------------------------
    await s.rateSeries.append(
      RateObservation(
        currency: CurrencyCode('VES'),
        nativePerUsd: Decimal.parse('840.00'),
        observedAt: _dayManual,
        source: 'manual:paralelo',
      ),
    );

    final manualDayResolution = await RateResolutionService(s.rateSeries)(
      CurrencyCode('VES'),
      asOf: _dayManual,
    );
    expect(manualDayResolution!.source, equals('manual:paralelo'));
    expect(manualDayResolution.nativePerUsd, equals(Decimal.parse('840.00')));

    await s.quickAddExpense.call(
      eventId: EventId('evt-day-manual'),
      deviceId: 'dev-test',
      accountId: _vesId,
      envelopeId: _groceriesId,
      amount: _tenThousandBs,
      occurredAt: DomainTimestamp(_dayManual),
    );
    _expectSelfBalancing(
      s.catalog,
      s.projections,
      reason: 'after the manually-rated expense',
    );
    await _expectExpenseFrozeAt(
      store: s.store,
      eventId: EventId('evt-day-manual'),
      expectedUsdCents: 1190,
      expectedRateText: '840.00',
      notExpectedRateText: '838.00',
    );
    expect(
      s.projections.envelopeUsdBalance(_groceriesId),
      equals(-1182 - 1195 - 1190),
    );

    // ---------------------------------------------------------------
    // 4b. The next day, a fresh automatic reading (847.00) exists and
    // no new manual entry does — the automatic takes over alone; the
    // prior day's manual does not leak forward.
    // ---------------------------------------------------------------
    final nextDayResolution = await RateResolutionService(s.rateSeries)(
      CurrencyCode('VES'),
      asOf: _dayAutoTakesOver,
    );
    expect(nextDayResolution!.source, equals('binancep2p:ask'));
    expect(nextDayResolution.nativePerUsd, equals(Decimal.parse('847.00')));

    await s.quickAddExpense.call(
      eventId: EventId('evt-day-auto-takes-over'),
      deviceId: 'dev-test',
      accountId: _vesId,
      envelopeId: _groceriesId,
      amount: _tenThousandBs,
      occurredAt: DomainTimestamp(_dayAutoTakesOver),
    );
    _expectSelfBalancing(
      s.catalog,
      s.projections,
      reason: 'after the automatic takes over',
    );
    await _expectExpenseFrozeAt(
      store: s.store,
      eventId: EventId('evt-day-auto-takes-over'),
      expectedUsdCents: 1181,
      expectedRateText: '847.00',
      notExpectedRateText: '840.00',
    );
    expect(
      s.projections.envelopeUsdBalance(_groceriesId),
      equals(-1182 - 1195 - 1190 - 1181),
    );

    // ---------------------------------------------------------------
    // 5. Offline, two days after the last observation: no new sync
    // happens, yet the expense still records, frozen with that stale
    // rate (847.00, from 2026-08-07).
    // ---------------------------------------------------------------
    await s.quickAddExpense.call(
      eventId: EventId('evt-offline-stale'),
      deviceId: 'dev-test',
      accountId: _vesId,
      envelopeId: _groceriesId,
      amount: _tenThousandBs,
      occurredAt: DomainTimestamp(_offlineToday),
    );
    _expectSelfBalancing(
      s.catalog,
      s.projections,
      reason: 'after the offline, stale-rated expense',
    );
    await _expectExpenseFrozeAt(
      store: s.store,
      eventId: EventId('evt-offline-stale'),
      expectedUsdCents: 1181,
      expectedRateText: '847.00',
      notExpectedRateText: '840.00',
    );
    expect(
      s.projections.envelopeUsdBalance(_groceriesId),
      equals(-1182 - 1195 - 1190 - 1181 - 1181),
    );

    // ---------------------------------------------------------------
    // 6. A historical rate: an expense backdated to 2026-08-04 freezes
    // with that day's observation (845.88), not the latest one in the
    // series (847.00) — ADR-0019 §5's promise, now with automatic
    // sources too.
    // ---------------------------------------------------------------
    await s.quickAddExpense.call(
      eventId: EventId('evt-historical'),
      deviceId: 'dev-test',
      accountId: _vesId,
      envelopeId: _groceriesId,
      amount: _tenThousandBs,
      occurredAt: DomainTimestamp(_dayA),
    );
    _expectSelfBalancing(
      s.catalog,
      s.projections,
      reason: 'after the historically-rated expense',
    );
    await _expectExpenseFrozeAt(
      store: s.store,
      eventId: EventId('evt-historical'),
      expectedUsdCents: 1182,
      expectedRateText: '845.88',
      notExpectedRateText: '847.00',
    );
    final totalEnvelopeUsd = -1182 - 1195 - 1190 - 1181 - 1181 - 1182;
    expect(
      s.projections.envelopeUsdBalance(_groceriesId),
      equals(totalEnvelopeUsd),
    );
    expect(
      s.projections.accountBalance(_vesId).native.amount,
      equals(BigInt.from(-6000000)),
      reason: 'six 10 000.00 Bs expenses withdrawn from a zero balance',
    );

    // ---------------------------------------------------------------
    // 7. Replay both dimensions: the ledger (fresh projections rebuilt
    // from the event log) and the rate series (fresh reader over the
    // same, still-open tasas database).
    // ---------------------------------------------------------------
    final accountSnapshot = s.projections.accountBalance(_vesId);
    final envelopeSnapshot = {
      for (final e in s.catalog.envelopes)
        e.id: s.projections.envelopeUsdBalance(e.id),
    };

    final catalog2 = DriftCatalogRepository(ledgerDb);
    await catalog2.hydrate();
    final projections2 = await _replayLedger(ledgerDb);
    final rateSeries2 = DriftRateSeries(ratesDb);

    final replayedAccount = projections2.accountBalance(_vesId);
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

    final replayedHistorical = await RateResolutionService(rateSeries2)(
      CurrencyCode('VES'),
      asOf: _dayA,
    );
    expect(replayedHistorical!.source, equals('binancep2p:ask'));
    expect(
      replayedHistorical.nativePerUsd,
      equals(Decimal.parse('845.88')),
      reason:
          'Replay: historical rate lookup still resolves to Day A\'s '
          'observation, not the latest one',
    );

    final replayedManualDay = await RateResolutionService(rateSeries2)(
      CurrencyCode('VES'),
      asOf: _dayManual,
    );
    expect(replayedManualDay!.source, equals('manual:paralelo'));
  });
}
