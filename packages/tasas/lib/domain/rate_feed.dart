import 'rate_observation.dart';

/// Port for the app's first network consumer (S2, ADR-0020 §1): downloads
/// the NDJSON feed the `rates` worker publishes and returns what it
/// contains. Fails silent — a feed that can't be reached returns no
/// observations rather than throwing, so a sync never blocks the app or
/// surfaces a network error (ADR-0020 §6).
abstract class RateFeed {
  Future<List<RateObservation>> fetch();
}
