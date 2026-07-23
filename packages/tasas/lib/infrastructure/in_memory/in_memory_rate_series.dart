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
  }) async {
    RateObservation? latest;
    for (final observation in _observations) {
      if (observation.currency != currency) continue;
      if (source != null && observation.source != source) continue;
      if (latest == null ||
          !observation.observedAt.isBefore(latest.observedAt)) {
        latest = observation;
      }
    }
    return latest;
  }
}
