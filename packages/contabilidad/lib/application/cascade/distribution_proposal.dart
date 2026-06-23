import 'package:shared_kernel/shared_kernel.dart';

/// One line in a [DistributionProposal]: how much goes to one envelope.
class AllocationLine {
  final EnvelopeId envelopeId;
  final int amountUsd;

  const AllocationLine({required this.envelopeId, required this.amountUsd});
}

/// Result of [CascadeEngine.run]: ordered list of per-envelope allocations.
/// Residue (no catch-all) stays in Stage — not represented here.
class DistributionProposal {
  final List<AllocationLine> allocations;

  const DistributionProposal(this.allocations);
}
