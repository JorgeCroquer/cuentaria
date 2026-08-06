import '../domain/rate_observation.dart';
import '../domain/rate_series.dart';

/// Records the manually-captured rates for a currency (ADR-0016 §4): BCV
/// and/or parallel, each appended as its own observation. Either may be
/// omitted — the form (#175) only supplies the series the user actually
/// typed a different value for, so accepting the Chain's suggestion for one
/// series never fabricates an observation for it.
class RecordRateUseCase {
  final RateSeries _series;

  RecordRateUseCase(this._series);

  Future<void> execute({
    RateObservation? bcv,
    RateObservation? paralelo,
  }) async {
    if (bcv == null && paralelo == null) {
      throw ArgumentError('at least one of bcv or paralelo must be given');
    }
    if (bcv != null && paralelo != null && bcv.currency != paralelo.currency) {
      throw ArgumentError('bcv and paralelo must observe the same currency');
    }
    if (bcv != null) await _series.append(bcv);
    if (paralelo != null) await _series.append(paralelo);
  }
}
