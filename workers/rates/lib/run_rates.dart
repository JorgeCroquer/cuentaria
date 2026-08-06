import 'package:tasas/domain/rate_observation.dart';
import 'package:tasas/infrastructure/ndjson/ndjson_rate_store.dart';

import 'sources/rate_source.dart';

/// Fetches every [sources] independently (ADR-0020 §2 — no source's failure
/// blocks another's) and merges what they report into [existingNdjson].
/// Returns the full merged feed, or null when there is nothing new to
/// publish — either every source failed or everything they reported was
/// already in the feed.
Future<String?> runRates({
  required String existingNdjson,
  required List<RateSource> sources,
}) async {
  final store = NdjsonRateStore.parse(existingNdjson);
  var addedAny = false;

  for (final source in sources) {
    List<RateObservation> observations;
    try {
      observations = await source.fetch();
    } catch (_) {
      observations = [];
    }
    for (final observation in observations) {
      if (store.append(observation)) addedAny = true;
    }
  }

  return addedAny ? store.serialize() : null;
}
