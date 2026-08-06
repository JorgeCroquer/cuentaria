import '../domain/rate_feed.dart';
import '../domain/rate_series.dart';

/// Mixes what [RateFeed] downloads into the local [RateSeries] (S2,
/// ADR-0020 §6): idempotent by `(currency, source, observedAt)` — syncing
/// the same feed twice appends nothing the second time. Never throws:
/// [RateFeed.fetch] already fails silent on any network error, so there is
/// nothing here to catch.
class SyncRateSeriesUseCase {
  final RateFeed _feed;
  final RateSeries _series;

  SyncRateSeriesUseCase(this._feed, this._series);

  Future<void> sync() async {
    final observations = await _feed.fetch();
    for (final observation in observations) {
      final existing = await _series.latestFor(
        observation.currency,
        source: observation.source,
        asOf: observation.observedAt,
      );
      if (existing != null &&
          existing.observedAt.isAtSameMomentAs(observation.observedAt)) {
        continue;
      }
      await _series.append(observation);
    }
  }
}
