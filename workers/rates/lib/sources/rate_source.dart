import 'package:tasas/domain/rate_observation.dart';

/// A public rate feed the worker polls independently (ADR-0020 §2): a
/// failure here never cascades, so [fetch] never throws — a source that
/// cannot be reached returns an empty list instead.
abstract class RateSource {
  Future<List<RateObservation>> fetch();
}
