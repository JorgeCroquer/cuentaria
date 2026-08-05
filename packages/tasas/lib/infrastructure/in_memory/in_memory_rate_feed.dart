import '../../domain/rate_feed.dart';
import '../../domain/rate_observation.dart';
import '../ndjson/ndjson_rate_store.dart';

/// Test/web adapter for [RateFeed]: parses a fixed NDJSON string instead of
/// making a network call.
class InMemoryRateFeed implements RateFeed {
  final List<RateObservation> _observations;

  InMemoryRateFeed(String ndjson)
    : _observations = NdjsonRateStore.parse(ndjson).observations;

  @override
  Future<List<RateObservation>> fetch() async => _observations;
}
