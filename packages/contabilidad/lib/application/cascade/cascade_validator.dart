import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/catalog/models/funding_target.dart';
import 'package:decimal/decimal.dart';
import 'package:shared_kernel/shared_kernel.dart';

import 'cascade.dart';
import 'cascade_step.dart';

/// Result of [CascadeValidator.validate].
class CascadeValidationResult {
  final List<String> errors;
  final List<String> warnings;

  const CascadeValidationResult({required this.errors, required this.warnings});

  bool get isValid => errors.isEmpty;
}

/// Edit-time validator for a [Cascade] (ADR-0015 §3).
///
/// Called when the user saves their cascade plan — NOT as a domain invariant.
/// The engine is total and degrades at runtime; this gives clear user feedback.
///
/// Rules (errors):
///   - At most one catch-all step; it must be last.
///   - [FixedStep.amountUsd] must be > 0.
///   - [PercentOfRemainderStep.percent] must be in (0, 1].
///   - Each step's target envelope must exist, have [EnvelopeRole.none], and not be archived.
///
/// Rules (warnings):
///   - [FillToCapStep] whose target has no [Cap] → warns but does not reject.
final class CascadeValidator {
  CascadeValidator._();

  static CascadeValidationResult validate({
    required Cascade cascade,
    required Map<EnvelopeId, Envelope> catalog,
  }) {
    final errors = <String>[];
    final warnings = <String>[];

    final steps = cascade.steps;

    // --- catch-all position ---
    final catchAllIndices = [
      for (var i = 0; i < steps.length; i++)
        if (steps[i] is CatchAllStep) i,
    ];

    if (catchAllIndices.length > 1) {
      errors.add(
        'Only one catch-all step is allowed; found ${catchAllIndices.length}.',
      );
    } else if (catchAllIndices.length == 1 &&
        catchAllIndices[0] != steps.length - 1) {
      errors.add(
        'The catch-all step must be last (found at position ${catchAllIndices[0] + 1} of ${steps.length}).',
      );
    }

    // --- per-step rules ---
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      final pos = i + 1; // 1-based for messages

      // envelope existence + usability
      final env = catalog[step.envelopeId];
      final usable =
          env != null && env.role == EnvelopeRole.none && !env.isArchived;
      if (env == null) {
        errors.add(
          'Step $pos: envelope "${step.envelopeId.value}" does not exist.',
        );
      } else {
        if (env.role != EnvelopeRole.none) {
          errors.add(
            'Step $pos: envelope "${step.envelopeId.value}" is a system envelope '
            '(role=${env.role.name}) and cannot be a cascade target.',
          );
        } else if (env.isArchived) {
          errors.add(
            'Step $pos: envelope "${step.envelopeId.value}" is archived.',
          );
        }
      }

      // type-specific rules
      switch (step) {
        case FixedStep(:final amountUsd):
          if (amountUsd <= 0) {
            errors.add('Step $pos: fixed amount must be > 0 (got $amountUsd).');
          }

        case FillToCapStep():
          if (usable && env.target is! Cap) {
            warnings.add(
              'Step $pos: envelope "${step.envelopeId.value}" has no cap; '
              'fill-to-cap will always contribute 0.',
            );
          }

        case PercentOfRemainderStep(:final percent):
          if (percent <= Decimal.zero || percent > Decimal.one) {
            errors.add('Step $pos: percent must be in (0, 1] (got $percent).');
          }

        case CatchAllStep():
          break; // position already checked above
      }
    }

    return CascadeValidationResult(errors: errors, warnings: warnings);
  }
}
