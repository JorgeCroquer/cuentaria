import 'package:decimal/decimal.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'cascade_step.dart';
import 'distribution_proposal.dart';
import 'envelope_state.dart';

/// Pure engine: distributes [amount] cents across envelopes according to
/// an ordered [steps] plan.
///
/// Contract (ADR-0015 C2-4/C2-5):
/// - Single [remaining] counter; universal clamp `give = min(calc, remaining)`.
/// - Never throws — missing state skips step, fillToCap without cap gives 0.
/// - All amounts are integer USD cents; no doubles in output.
final class CascadeEngine {
  CascadeEngine._();

  static DistributionProposal run({
    required int amount,
    required List<CascadeStep> steps,
    required Map<EnvelopeId, EnvelopeState> envelopeStates,
  }) {
    var remaining = amount;
    final lines = <AllocationLine>[];

    for (final step in steps) {
      final state = envelopeStates[step.envelopeId];
      if (state == null) continue; // missing target → skip (total engine)

      final calc = switch (step) {
        FixedStep(:final amountUsd) => amountUsd,
        FillToCapStep() => _fillToCapCalc(state),
        PercentOfRemainderStep(:final percent, :final base) => _percentCalc(
          percent,
          base,
          amount,
          remaining,
        ),
        CatchAllStep() => remaining,
      };

      final give = calc < remaining ? calc : remaining; // min(calc, remaining)
      final clamped = give < 0 ? 0 : give; // never negative
      remaining -= clamped;
      lines.add(
        AllocationLine(envelopeId: step.envelopeId, amountUsd: clamped),
      );
    }

    return DistributionProposal(lines);
  }

  static int _fillToCapCalc(EnvelopeState state) {
    final cap = state.capUsd;
    if (cap == null) return 0; // no cap → 0 (total engine)
    final deficit = cap - state.balanceUsd;
    return deficit > 0 ? deficit : 0;
  }

  static int _percentCalc(
    Decimal percent,
    PercentBase base,
    int grossAmount,
    int remaining,
  ) {
    final basis = base == PercentBase.gross ? grossAmount : remaining;
    final result = (Decimal.fromInt(basis) * percent).round();
    return result.toBigInt().toInt();
  }
}
