import 'package:decimal/decimal.dart';
import 'package:shared_kernel/shared_kernel.dart';

/// Calibration knob for [CascadeStep.percentOfRemainder].
enum PercentBase { remainder, gross }

/// A single step in an ordered cascade plan.
/// Sealed — exactly 4 variants, no others.
sealed class CascadeStep {
  final EnvelopeId envelopeId;
  const CascadeStep({required this.envelopeId});

  const factory CascadeStep.fixed({
    required EnvelopeId envelopeId,
    required int amountUsd,
  }) = FixedStep;

  const factory CascadeStep.fillToCap({
    required EnvelopeId envelopeId,
  }) = FillToCapStep;

  // ponytail: Decimal (not const) — no const factory; other steps keep const.
  factory CascadeStep.percentOfRemainder({
    required EnvelopeId envelopeId,
    required Decimal percent,
    required PercentBase base,
  }) = PercentOfRemainderStep;

  const factory CascadeStep.catchAll({
    required EnvelopeId envelopeId,
  }) = CatchAllStep;
}

final class FixedStep extends CascadeStep {
  final int amountUsd;
  const FixedStep({required super.envelopeId, required this.amountUsd});
}

final class FillToCapStep extends CascadeStep {
  const FillToCapStep({required super.envelopeId});
}

final class PercentOfRemainderStep extends CascadeStep {
  final Decimal percent;
  final PercentBase base;
  PercentOfRemainderStep({
    required super.envelopeId,
    required this.percent,
    required this.base,
  });
}

final class CatchAllStep extends CascadeStep {
  const CatchAllStep({required super.envelopeId});
}
