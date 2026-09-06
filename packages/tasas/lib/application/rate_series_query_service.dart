import 'package:shared_kernel/shared_kernel.dart';

import '../domain/rate_observation.dart';
import '../domain/rate_series.dart';

/// Read-only queries over the observation history for the Serie de tasas
/// screen (#261, ADR-0020 deferred it "a territorio S5") — orchestrates
/// [RateSeries.allObservations] so the UI never scans the raw series itself.
class RateSeriesQueryService {
  final RateSeries _series;

  RateSeriesQueryService(this._series);

  /// Currencies with at least one recorded observation, in the order they
  /// were first observed — the only ones the currency selector may offer,
  /// since a currency with no data has nothing to chart.
  Future<List<CurrencyCode>> currenciesWithObservations() async {
    final observations = await _series.allObservations();
    final seen = <CurrencyCode>{};
    final currencies = <CurrencyCode>[];
    for (final observation in observations) {
      if (seen.add(observation.currency)) currencies.add(observation.currency);
    }
    return currencies;
  }

  /// Observations for [currency] in the [monthsBack] months up to [asOf]
  /// (defaults to now), oldest first — the window the chart plots.
  Future<List<RateObservation>> observationsFor(
    CurrencyCode currency, {
    int monthsBack = 12,
    DateTime? asOf,
  }) async {
    final cutoffEnd = asOf ?? DateTime.now().toUtc();
    final cutoffStart = DateTime.utc(
      cutoffEnd.year,
      cutoffEnd.month - monthsBack,
      cutoffEnd.day,
    );
    final observations = await _series.allObservations();
    return observations
        .where(
          (observation) =>
              observation.currency == currency &&
              !observation.observedAt.isBefore(cutoffStart) &&
              !observation.observedAt.isAfter(cutoffEnd),
        )
        .toList();
  }
}
