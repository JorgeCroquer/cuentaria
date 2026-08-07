import 'package:shared_kernel/shared_kernel.dart';

import '../../domain/rate_observation.dart';
import '../../domain/rate_series.dart';

class InMemoryRateSeries implements RateSeries {
  final List<RateObservation> _observations = [];

  @override
  Future<void> append(RateObservation observation) async {
    _observations.add(observation);
  }

  @override
  Future<RateObservation?> latestFor(
    CurrencyCode currency, {
    String? source,
    DateTime? asOf,
  }) async {
    RateObservation? latest;
    for (final observation in _observations) {
      if (observation.currency != currency) continue;
      if (source != null && observation.source != source) continue;
      if (asOf != null && observation.observedAt.isAfter(asOf)) continue;
      if (latest == null ||
          !observation.observedAt.isBefore(latest.observedAt)) {
        latest = observation;
      }
    }
    return latest;
  }

  @override
  Future<List<RateObservation>> candidatesFor(
    CurrencyCode currency, {
    DateTime? asOf,
  }) async {
    final latestBySource = <String, RateObservation>{};
    for (final observation in _observations) {
      if (observation.currency != currency) continue;
      if (asOf != null && observation.observedAt.isAfter(asOf)) continue;
      final current = latestBySource[observation.source];
      if (current == null ||
          !observation.observedAt.isBefore(current.observedAt)) {
        latestBySource[observation.source] = observation;
      }
    }
    return latestBySource.values.toList();
  }

  @override
  Future<List<RateObservation>> allObservations() async {
    final sorted = List<RateObservation>.from(_observations)
      ..sort((a, b) => a.observedAt.compareTo(b.observedAt));
    return sorted;
  }
}
