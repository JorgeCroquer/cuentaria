import 'package:decimal/decimal.dart';
import 'package:shared_kernel/shared_kernel.dart';

import 'cascade_step.dart';

/// Canonical JSON shape for a [CascadeStep] list — the single source of
/// truth [DriftCascadeRepository] persists and the Backup File (ADR-0021)
/// reuses, so the two never drift out of sync with each other.
class CascadeCodec {
  const CascadeCodec._();

  static List<Map<String, dynamic>> stepsToJson(List<CascadeStep> steps) =>
      steps.map(_stepToJson).toList();

  static List<CascadeStep> stepsFromJson(List<Map<String, dynamic>> json) =>
      json.map(_stepFromJson).toList();

  static Map<String, dynamic> _stepToJson(CascadeStep step) => switch (step) {
    FixedStep(:final envelopeId, :final amountUsd) => {
      'type': 'fixed',
      'envelope_id': envelopeId.value,
      'amount_usd': amountUsd,
    },
    FillToCapStep(:final envelopeId) => {
      'type': 'fill_to_cap',
      'envelope_id': envelopeId.value,
    },
    PercentOfRemainderStep(:final envelopeId, :final percent, :final base) => {
      'type': 'percent_of_remainder',
      'envelope_id': envelopeId.value,
      'percent': percent.toString(),
      'base': base.name,
    },
    CatchAllStep(:final envelopeId) => {
      'type': 'catch_all',
      'envelope_id': envelopeId.value,
    },
  };

  static CascadeStep _stepFromJson(Map<String, dynamic> j) {
    final type = j['type'] as String;
    final envelopeId = EnvelopeId(j['envelope_id'] as String);
    return switch (type) {
      'fixed' => CascadeStep.fixed(
        envelopeId: envelopeId,
        amountUsd: j['amount_usd'] as int,
      ),
      'fill_to_cap' => CascadeStep.fillToCap(envelopeId: envelopeId),
      'percent_of_remainder' => CascadeStep.percentOfRemainder(
        envelopeId: envelopeId,
        percent: Decimal.parse(j['percent'] as String),
        base: PercentBase.values.byName(j['base'] as String),
      ),
      'catch_all' => CascadeStep.catchAll(envelopeId: envelopeId),
      _ => throw FormatException('Unknown CascadeStep type: $type'),
    };
  }
}
