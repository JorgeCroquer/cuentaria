import 'cascade.dart';

/// Port: stores and reads the single user cascade plan (LWW config).
///
/// Only one cascade exists per user at any time (MVP constraint, ADR-0015 §1).
abstract class CascadeRepository {
  /// Returns the current cascade, or null if none has been saved.
  Future<Cascade?> load();

  /// Persists [cascade], merging with any existing copy using LWW on [Cascade.updatedAt].
  Future<void> save(Cascade cascade);
}
