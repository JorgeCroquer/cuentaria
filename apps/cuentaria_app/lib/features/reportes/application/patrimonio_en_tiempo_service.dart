import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/domain/ports/event_store.dart';
import 'package:contabilidad/domain/ports/log_filters.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:deudas/deudas.dart' as deudas;
import 'package:patrimonio/patrimonio.dart';
import 'package:reportes/reportes.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/application/rate_resolution_service.dart';
import 'package:tasas/domain/rate_resolver.dart';
import 'package:tasas/domain/rate_series.dart';

const _engine = PatrimonioEngine();
const _debtsEngine = deudas.DebtsEngine();
final _usd = CurrencyCode('USD');

/// Patrimonio en el tiempo (#260, ADR-0024 §5-6): twelve Net Worth Points,
/// one per month-end, computed by replaying the ledger to each cutoff into
/// a throwaway [InMemoryLedgerProjections] and feeding the existing
/// [PatrimonioEngine] — no persisted snapshot, no interpolation. Debt
/// Accounts are excluded from [PatrimonioEngine]'s input and replayed
/// through [DebtsEngine] instead, then folded back into the point's totals
/// — the same "segregating moves presentation, not numbers" mapping
/// `patrimonio_providers.dart`'s `patrimonioSnapshotProvider` does for
/// "today" (#207), so each point stays at parity with it.
///
/// Archived accounts still count in the months they held a balance: unlike
/// "Patrimonio hoy", [AccountView.isArchived] is always passed as `false`
/// here, since the engine would otherwise drop a currency group at its
/// *current* archive status rather than its historical one — the replayed
/// balance itself (zero once emptied) already tells the honest story.
class PatrimonioEnTiempoService {
  PatrimonioEnTiempoService({
    required EventStore eventStore,
    required CatalogRepository catalog,
    required RateSeries rateSeries,
  }) : _eventStore = eventStore,
       _catalog = catalog,
       _rateSeries = rateSeries;

  final EventStore _eventStore;
  final CatalogRepository _catalog;
  final RateSeries _rateSeries;

  Future<List<PatrimonioPoint>> calculatePoints({
    required ReportMonth latestMonth,
    int monthsCount = 12,
  }) async {
    final months = _lastMonths(latestMonth, monthsCount);
    final points = <PatrimonioPoint>[];
    for (final month in months) {
      points.add(await _pointFor(month));
    }
    return points;
  }

  List<ReportMonth> _lastMonths(ReportMonth latest, int count) {
    final months = <ReportMonth>[];
    var cursor = latest;
    for (var i = 0; i < count; i++) {
      months.add(cursor);
      cursor = cursor.previousMonth;
    }
    return months.reversed.toList();
  }

  Future<PatrimonioPoint> _pointFor(ReportMonth month) async {
    final cutoff = month.endOfMonth.toUtc();
    final projections = InMemoryLedgerProjections();
    final events = await _eventStore.queryLog(
      filters: LogFilters(to: DomainTimestamp(cutoff)),
    );
    for (final event in events) {
      projections.apply(event);
    }

    final accounts = [
      for (final account in _catalog.accounts)
        if (!account.isDebtAccount)
          AccountView(
            id: account.id,
            currency: account.nativeCurrency,
            nativeMinorAmount:
                projections.accountBalance(account.id).native.amount,
            realCostUsdCents: projections.accountBalance(account.id).usd,
            isArchived: false,
          ),
    ];

    final debtAccounts = [
      for (final account in _catalog.accounts)
        if (account.isDebtAccount)
          deudas.DebtAccountView(
            id: account.id,
            counterpartyName: account.counterpartyName!,
            currency: account.nativeCurrency,
            nativeMinorAmount:
                projections.accountBalance(account.id).native.amount,
            realCostUsdCents: projections.accountBalance(account.id).usd,
            isArchived: false,
          ),
    ];

    final foreignCurrencies =
        {
          ...accounts.map((a) => a.currency),
          ...debtAccounts.map((a) => a.currency),
        }.where((c) => c != _usd).toSet();

    final rates = <CurrencyCode, RateView>{};
    final debtRates = <CurrencyCode, deudas.RateView>{};
    for (final currency in foreignCurrencies) {
      final parallel = await RateResolutionService(_rateSeries)(
        currency,
        asOf: cutoff,
      );
      final bcv = await RateResolutionService(_rateSeries)(
        currency,
        asOf: cutoff,
        sourcePriority: oficialSourcePriority,
      );
      if (parallel == null && bcv == null) continue;

      final parallelView =
          parallel == null
              ? null
              : RateObservationView(
                nativePerUsd: parallel.nativePerUsd,
                observedAt: parallel.observedAt,
                source: parallel.source,
              );
      final bcvView =
          bcv == null
              ? null
              : RateObservationView(
                nativePerUsd: bcv.nativePerUsd,
                observedAt: bcv.observedAt,
                source: bcv.source,
              );

      rates[currency] = RateView(
        currency: currency,
        parallel: parallelView,
        bcv: bcvView,
      );
      debtRates[currency] = deudas.RateView(
        currency: currency,
        parallel:
            parallel == null
                ? null
                : deudas.RateObservationView(
                  nativePerUsd: parallel.nativePerUsd,
                  observedAt: parallel.observedAt,
                  source: parallel.source,
                ),
        bcv:
            bcv == null
                ? null
                : deudas.RateObservationView(
                  nativePerUsd: bcv.nativePerUsd,
                  observedAt: bcv.observedAt,
                  source: bcv.source,
                ),
      );
    }

    final snapshot = _engine(accounts, rates, const [], cutoff);
    final debtsSnapshot = _debtsEngine(debtAccounts, debtRates, cutoff);

    // Debt Accounts are excluded from `accounts` above (#207) so they never
    // land in a currency group — their totals are added back here so
    // segregating them moves presentation, not numbers, matching
    // patrimonioSnapshotProvider's "today" mapping.
    final debtsRealCostUsdCents = [
      for (final persona in debtsSnapshot.personas)
        for (final leg in persona.currencies) leg.realCostUsdCents,
    ].fold(0, (sum, cost) => sum + cost);
    final realCostUsdCents = snapshot.realCostUsdCents + debtsRealCostUsdCents;
    final marketValueUsdCents =
        snapshot.hasMissingRate
            ? null
            : snapshot.todayValueUsdCents + debtsSnapshot.globalNetoUsdCents;

    String? rateSource;
    DateTime? rateObservedAt;
    if (!snapshot.hasMissingRate) {
      for (final group in snapshot.accountGroups) {
        if (group.currency == _usd) continue;
        final rate = group.parallelRate;
        if (rate != null) {
          rateSource = rate.source;
          rateObservedAt = rate.observedAt;
          break;
        }
      }
    }

    return PatrimonioPoint(
      month: month,
      realCostUsdCents: realCostUsdCents,
      marketValueUsdCents: marketValueUsdCents,
      rateSource: rateSource,
      rateObservedAt: rateObservedAt,
    );
  }
}
