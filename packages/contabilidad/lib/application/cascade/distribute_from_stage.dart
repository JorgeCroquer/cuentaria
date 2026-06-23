import 'package:shared_kernel/shared_kernel.dart';

import 'cascade_engine.dart';
import 'cascade_repository.dart';
import 'distribution_proposal.dart';
import 'envelope_state.dart';
import 'cascade_step.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models/envelope.dart';
import '../catalog/models/funding_target.dart';
import '../ledger/factories/record_distribution.dart';
import '../../domain/ports/ledger_projections.dart';

/// Orchestrates a cascade distribution run:
///   1. Reads Stage balance + each target envelope state.
///   2. Runs [CascadeEngine] over the saved cascade.
///   3. Exposes the [DistributionProposal] for preview / skip.
///   4. On apply, translates to [RecordDistribution] entries (Σ = 0).
///
/// Guard: amount ≤ Stage balance (never pushes Stage negative).
/// Residue without catchAll stays in Stage (no entry generated for it).
/// ADR-0015 C2-6, Model A.
class DistributeFromStage {
  final LedgerProjections _projections;
  final CatalogRepository _catalog;
  final CascadeRepository _cascadeRepo;
  final RecordDistribution _recordDistribution;

  DistributeFromStage({
    required LedgerProjections projections,
    required CatalogRepository catalog,
    required CascadeRepository cascadeRepo,
    required RecordDistribution recordDistribution,
  }) : _projections = projections,
       _catalog = catalog,
       _cascadeRepo = cascadeRepo,
       _recordDistribution = recordDistribution;

  // -- Public API ---------------------------------------------------------

  /// Returns a [DistributionProposal] using the full cascade and current
  /// Stage balance as amount, without posting anything.
  /// Returns null if no cascade is saved yet.
  Future<DistributionProposal?> preview({int? amount}) async {
    final cascade = await _cascadeRepo.load();
    if (cascade == null) return null;
    return _run(steps: cascade.steps, amount: amount);
  }

  /// Applies the full cascade to the ledger.
  Future<void> apply({
    required EventId eventId,
    required String deviceId,
    int? amount,
  }) async {
    final cascade = await _cascadeRepo.load();
    if (cascade == null) return;
    await _applySteps(
      steps: cascade.steps,
      amount: amount,
      eventId: eventId,
      deviceId: deviceId,
    );
  }

  /// Applies the cascade, skipping any step whose [envelopeId] is in
  /// [skipEnvelopeIds]. Identical to running the engine with a filtered list.
  Future<void> applySkipping({
    required Set<EnvelopeId> skipEnvelopeIds,
    required EventId eventId,
    required String deviceId,
    int? amount,
  }) async {
    final cascade = await _cascadeRepo.load();
    if (cascade == null) return;
    final filtered =
        cascade.steps
            .where((s) => !skipEnvelopeIds.contains(s.envelopeId))
            .toList();
    await _applySteps(
      steps: filtered,
      amount: amount,
      eventId: eventId,
      deviceId: deviceId,
    );
  }

  // -- Private ------------------------------------------------------------

  int _stageBalance() {
    final stageId = _catalog.getSystemEnvelope(EnvelopeRole.stage);
    return _projections.envelopeUsdBalance(stageId);
  }

  Map<EnvelopeId, EnvelopeState> _buildStates(List<CascadeStep> steps) {
    final states = <EnvelopeId, EnvelopeState>{};
    for (final step in steps) {
      final env = _catalog.getEnvelope(step.envelopeId);
      if (env == null || env.isArchived) continue; // total engine: skip
      final balance = _projections.envelopeUsdBalance(step.envelopeId);
      final capUsd = switch (env.target) {
        Cap(:final amountUsd) => amountUsd,
        _ => null,
      };
      states[step.envelopeId] = EnvelopeState(
        balanceUsd: balance,
        capUsd: capUsd,
      );
    }
    return states;
  }

  DistributionProposal _run({required List<CascadeStep> steps, int? amount}) {
    final stageBalance = _stageBalance();
    final effectiveAmount = amount ?? stageBalance;
    return CascadeEngine.run(
      amount: effectiveAmount,
      steps: steps,
      envelopeStates: _buildStates(steps),
    );
  }

  Future<void> _applySteps({
    required List<CascadeStep> steps,
    required EventId eventId,
    required String deviceId,
    int? amount,
  }) async {
    final stageBalance = _stageBalance();
    final effectiveAmount = amount ?? stageBalance;

    if (effectiveAmount > stageBalance) {
      throw ArgumentError(
        'amount ($effectiveAmount) exceeds Stage balance ($stageBalance); '
        'Stage must never go negative.',
      );
    }

    if (effectiveAmount == 0) return; // nothing to distribute

    final proposal = _run(steps: steps, amount: effectiveAmount);

    final nonZero = proposal.allocations.where((a) => a.amountUsd > 0).toList();
    if (nonZero.isEmpty) return; // no-op

    final stageId = _catalog.getSystemEnvelope(EnvelopeRole.stage);
    final totalAllocated = nonZero.fold(0, (s, a) => s + a.amountUsd);

    final entries = [
      DistributionEntry(envelopeId: stageId, amountUsd: -totalAllocated),
      ...nonZero.map(
        (a) =>
            DistributionEntry(envelopeId: a.envelopeId, amountUsd: a.amountUsd),
      ),
    ];

    await _recordDistribution(
      eventId: eventId,
      deviceId: deviceId,
      entries: entries,
    );
  }
}
