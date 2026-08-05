import 'package:shared_kernel/shared_kernel.dart';

import 'rate_observation.dart';

/// Port for the append-only exchange rate observation series (ADR-0016).
abstract class RateSeries {
  Future<void> append(RateObservation observation);

  /// Most recent observation for [currency], or null if none was recorded.
  /// When [source] is given, scopes to observations from that exact source
  /// (e.g. `manual:bcv` vs `manual:paralelo`) instead of the latest overall.
  /// When [asOf] is given, scopes to the most recent observation at or
  /// before that instant instead of the latest overall — for valuing a
  /// movement registered late with the rate from when it actually happened
  /// (ADR-0019 §5). Omitting it preserves the current "latest overall"
  /// behavior exactly.
  Future<RateObservation?> latestFor(
    CurrencyCode currency, {
    String? source,
    DateTime? asOf,
  });
}
