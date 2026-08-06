import 'package:shared_kernel/shared_kernel.dart';

import '../domain/rate_resolver.dart';
import '../domain/rate_series.dart';

/// The single call site for the Rate Resolution Chain (#165): fetches the
/// latest observation per source from [RateSeries] and hands them to the
/// pure [resolve], so use cases and providers never touch
/// [RateSeries.candidatesFor] or [resolve] directly.
class RateResolutionService {
  final RateSeries _series;

  RateResolutionService(this._series);

  Future<Resolution?> call(CurrencyCode currency, {DateTime? asOf}) async {
    final cutoff = asOf ?? DateTime.now().toUtc();
    final candidates = await _series.candidatesFor(currency, asOf: cutoff);
    return resolve(currency, cutoff, candidates);
  }
}
