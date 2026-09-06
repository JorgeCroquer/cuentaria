import 'package:equatable/equatable.dart';
import 'package:shared_kernel/shared_kernel.dart';

import 'funding_target_view.dart';

/// Reportes-owned read view of a user Envelope carrying a [FundingTargetView]
/// (ADR-0005): [FundingPaceEngine] takes only this — app-layer wiring maps
/// contabilidad's Envelope + current balance into it beforehand, mirroring
/// `patrimonio`'s own `EnvelopeView`.
class FundingEnvelopeView extends Equatable {
  final EnvelopeId id;
  final String name;
  final int balanceUsdCents;
  final FundingTargetView target;

  const FundingEnvelopeView({
    required this.id,
    required this.name,
    required this.balanceUsdCents,
    required this.target,
  });

  @override
  List<Object?> get props => [id, name, balanceUsdCents, target];
}
