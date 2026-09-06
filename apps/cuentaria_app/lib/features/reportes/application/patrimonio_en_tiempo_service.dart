import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/domain/ports/event_store.dart';
import 'package:contabilidad/domain/ports/log_filters.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:patrimonio/patrimonio.dart';
import 'package:reportes/reportes.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/application/rate_resolution_service.dart';
import 'package:tasas/domain/rate_resolver.dart';
import 'package:tasas/domain/rate_series.dart';

const _engine = PatrimonioEngine();
final _usd = CurrencyCode('USD');

/// Patrimonio en el tiempo (#260, ADR-0024 §5-6): twelve Net Worth Points,
/// one per month-end, computed by replaying the ledger to each cutoff into
/// a throwaway [InMemoryLedgerProjections] and feeding the existing
/// [PatrimonioEngine] — no persisted snapshot, no interpolation. Debt
/// Accounts are excluded, matching [PatrimonioEngine]'s "today" mapping
/// (patrimonio_providers.dart, #207).
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

    final foreignCurrencies =
        accounts.map((a) => a.currency).where((c) => c != _usd).toSet();

    final rates = <CurrencyCode, RateView>{};
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

      rates[currency] = RateView(
        currency: currency,
        parallel:
            parallel == null
                ? null
                : RateObservationView(
                  nativePerUsd: parallel.nativePerUsd,
                  observedAt: parallel.observedAt,
                  source: parallel.source,
                ),
        bcv:
            bcv == null
                ? null
                : RateObservationView(
                  nativePerUsd: bcv.nativePerUsd,
                  observedAt: bcv.observedAt,
                  source: bcv.source,
                ),
      );
    }

    final snapshot = _engine(accounts, rates, const [], cutoff);

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
      realCostUsdCents: snapshot.realCostUsdCents,
      marketValueUsdCents:
          snapshot.hasMissingRate ? null : snapshot.todayValueUsdCents,
      rateSource: rateSource,
      rateObservedAt: rateObservedAt,
    );
  }
}
