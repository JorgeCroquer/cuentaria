import 'cascade_step.dart';

/// The single ordered cascade plan for the user.
///
/// Held as LWW config (like the catalog, ADR-0015 §1).
/// [steps] order = funding priority.
class Cascade {
  final List<CascadeStep> steps;
  final DateTime updatedAt;

  const Cascade({required this.steps, required this.updatedAt});

  /// Merges with [other] using last-write-wins on [updatedAt].
  Cascade mergeWith(Cascade other) =>
      other.updatedAt.isAfter(updatedAt) ? other : this;
}
