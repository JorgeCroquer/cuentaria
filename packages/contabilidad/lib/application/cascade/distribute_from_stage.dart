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
///   1. Reads the source envelope's balance + each target envelope state.
///   2. Runs [CascadeEngine] over the saved cascade.
///   3. Exposes the [DistributionProposal] for preview / skip.
///   4. On apply, translates to [RecordDistribution] entries (Σ = 0).
///
/// Source defaults to Stage but also accepts Apertura ([sourceRole]) — same
/// cascade, same preview/skip/apply mechanics (#96). Guard: amount ≤ source
/// balance (never pushes it negative). Residue without catchAll stays in the
/// source envelope (no entry generated for it).
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

  /// Returns a [DistributionProposal] using the full cascade and the current
  /// [sourceRole] balance as amount, without posting anything.
  /// Returns null if no cascade is saved yet.
  Future<DistributionProposal?> preview({
    int? amount,
    EnvelopeRole sourceRole = EnvelopeRole.stage,
  }) async {
    final cascade = await _cascadeRepo.load();
    if (cascade == null) return null;
    return _run(steps: cascade.steps, amount: amount, sourceRole: sourceRole);
  }

  /// Applies the full cascade to the ledger.
  Future<void> apply({
    required EventId eventId,
    required String deviceId,
    int? amount,
    EnvelopeRole sourceRole = EnvelopeRole.stage,
  }) async {
    final cascade = await _cascadeRepo.load();
    if (cascade == null) return;
    await _applySteps(
      steps: cascade.steps,
      amount: amount,
      eventId: eventId,
      deviceId: deviceId,
      sourceRole: sourceRole,
    );
  }

  /// Applies the cascade, skipping any step whose [envelopeId] is in
  /// [skipEnvelopeIds]. Identical to running the engine with a filtered list.
  Future<void> applySkipping({
    required Set<EnvelopeId> skipEnvelopeIds,
    required EventId eventId,
    required String deviceId,
    int? amount,
    EnvelopeRole sourceRole = EnvelopeRole.stage,
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
      sourceRole: sourceRole,
    );
  }

  // -- Private ------------------------------------------------------------

  int _sourceBalance(EnvelopeRole sourceRole) {
    final sourceId = _catalog.getSystemEnvelope(sourceRole);
    return _projections.envelopeUsdBalance(sourceId);
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

  DistributionProposal _run({
    required List<CascadeStep> steps,
    int? amount,
    EnvelopeRole sourceRole = EnvelopeRole.stage,
  }) {
    final sourceBalance = _sourceBalance(sourceRole);
    final effectiveAmount = amount ?? sourceBalance;
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
    EnvelopeRole sourceRole = EnvelopeRole.stage,
  }) async {
    final sourceBalance = _sourceBalance(sourceRole);
    final effectiveAmount = amount ?? sourceBalance;

    if (effectiveAmount > sourceBalance) {
      throw ArgumentError(
        'amount ($effectiveAmount) exceeds ${sourceRole.name} balance '
        '($sourceBalance); ${sourceRole.name} must never go negative.',
      );
    }

    if (effectiveAmount == 0) return; // nothing to distribute

    final proposal = _run(
      steps: steps,
      amount: effectiveAmount,
      sourceRole: sourceRole,
    );

    final nonZero = proposal.allocations.where((a) => a.amountUsd > 0).toList();
    if (nonZero.isEmpty) return; // no-op

    final sourceId = _catalog.getSystemEnvelope(sourceRole);
    final totalAllocated = nonZero.fold(0, (s, a) => s + a.amountUsd);

    final entries = [
      DistributionEntry(envelopeId: sourceId, amountUsd: -totalAllocated),
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
