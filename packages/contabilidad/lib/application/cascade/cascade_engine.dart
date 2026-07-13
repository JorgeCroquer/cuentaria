import 'package:shared_kernel/shared_kernel.dart';
import 'package:contabilidad/domain/cascade/cascade.dart';
import 'package:contabilidad/domain/cascade/cascade_step.dart';
import 'package:contabilidad/domain/cascade/distribution_proposal.dart';

class CascadeEngine {
  const CascadeEngine._();

  static DistributionProposal run(
    Money amount,
    Cascade cascade,
    Map<EnvelopeId, Money> envelopeStates,
  ) {
    final movements = <EnvelopeId, Money>{};
    var remaining = amount.amount;

    for (final step in cascade.steps) {
      if (remaining <= BigInt.zero) break;

      switch (step) {
        case FixedCascadeStep(:final target, :final amountUsd):
          if (amountUsd.currency != amount.currency) continue;
          if (!envelopeStates.containsKey(target)) continue;

          final give =
              amountUsd.amount <= remaining ? amountUsd.amount : remaining;
          if (give <= BigInt.zero) continue;

          final given = Money(amount: give, currency: amount.currency);
          movements[target] = (movements[target] ?? Money.zero(amount.currency))
              .add(given);
          remaining -= give;
      }
    }

    return DistributionProposal(amount.currency, movements);
  }
}
