import '../domain/rate_observation.dart';
import '../domain/rate_series.dart';

/// Records the two manually-captured rates for a currency (ADR-0016 §4):
/// BCV and parallel, each appended as its own observation.
class RecordRateUseCase {
  final RateSeries _series;

  RecordRateUseCase(this._series);

  Future<void> execute({
    required RateObservation bcv,
    required RateObservation paralelo,
  }) async {
    if (bcv.currency != paralelo.currency) {
      throw ArgumentError('bcv and paralelo must observe the same currency');
    }
    await _series.append(bcv);
    await _series.append(paralelo);
  }
}
