import 'package:shared_kernel/shared_kernel.dart';

import 'rate_observation.dart';

/// Port for the append-only exchange rate observation series (ADR-0016).
abstract class RateSeries {
  Future<void> append(RateObservation observation);

  /// Most recent observation for [currency], or null if none was recorded.
  Future<RateObservation?> latestFor(CurrencyCode currency);
}
