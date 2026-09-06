import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/domain/ports/event_store.dart';
import 'package:contabilidad/domain/ports/log_filters.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:deudas/deudas.dart' as deudas;
import 'package:reportes/reportes.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/application/rate_resolution_service.dart';
import 'package:tasas/domain/rate_resolver.dart';
import 'package:tasas/domain/rate_series.dart';

const _debtsEngine = deudas.DebtsEngine();
final _usd = CurrencyCode('USD');

/// Deuda por persona en el tiempo (#265, mirrors #260's replay pattern): one
/// [DebtPoint] per month-end, computed by replaying the ledger to each
/// cutoff into a throwaway [InMemoryLedgerProjections] and feeding the
/// existing [deudas.DebtsEngine] — no persisted snapshot, no interpolation.
///
/// Archived Debt Accounts still count in the months they held a balance:
/// like [PatrimonioEnTiempoService], every account is passed to the engine
/// with `isArchived: false` so a settled balance (zero once repaid) tells
/// the honest story instead of the engine dropping it at its *current*
/// archive status.
class DebtsEnTiempoService {
  DebtsEnTiempoService({
    required EventStore eventStore,
    required CatalogRepository catalog,
    required RateSeries rateSeries,
  }) : _eventStore = eventStore,
       _catalog = catalog,
       _rateSeries = rateSeries;

  final EventStore _eventStore;
  final CatalogRepository _catalog;
  final RateSeries _rateSeries;

  Future<List<DebtPoint>> calculatePoints({
    required ReportMonth latestMonth,
    int monthsCount = 12,
  }) async {
    final months = _lastMonths(latestMonth, monthsCount);
    final points = <DebtPoint>[];
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

  Future<DebtPoint> _pointFor(ReportMonth month) async {
    final cutoff = month.endOfMonth.toUtc();
    final projections = InMemoryLedgerProjections();
    final events = await _eventStore.queryLog(
      filters: LogFilters(to: DomainTimestamp(cutoff)),
    );
    for (final event in events) {
      projections.apply(event);
    }

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
        debtAccounts.map((a) => a.currency).where((c) => c != _usd).toSet();

    final debtRates = <CurrencyCode, deudas.RateView>{};
    String? rateSource;
    DateTime? rateObservedAt;
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

      if (parallel != null) {
        rateSource = parallel.source;
        rateObservedAt = parallel.observedAt;
      }
    }

    final debtsSnapshot = _debtsEngine(debtAccounts, debtRates, cutoff);

    final personas = [
      for (final persona in debtsSnapshot.personas)
        if (persona.netoUsdCents != 0)
          PersonDebtPoint(
            personName: persona.personName,
            netoUsdCents: persona.netoUsdCents,
          ),
    ];

    return DebtPoint(
      month: month,
      personas: personas,
      rateSource: rateSource,
      rateObservedAt: rateObservedAt,
    );
  }
}
