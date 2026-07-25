import 'package:equatable/equatable.dart';
import 'package:shared_kernel/shared_kernel.dart';

import 'envelope_view.dart';

/// One currency's accounts, valued (ADR-0016): [nativeMinorAmount] and
/// [realCostUsdCents] sum every non-archived account in this currency;
/// [todayValueUsdCents] and [bcvReferenceUsdCents] fall back to real cost
/// with [hasRate] false when no observation exists — never a silent 1:1.
class PatrimonioAccountGroup extends Equatable {
  final CurrencyCode currency;
  final BigInt nativeMinorAmount;
  final int realCostUsdCents;
  final int todayValueUsdCents;
  final int bcvReferenceUsdCents;
  final bool hasRate;
  final DateTime? observedAt;

  const PatrimonioAccountGroup({
    required this.currency,
    required this.nativeMinorAmount,
    required this.realCostUsdCents,
    required this.todayValueUsdCents,
    required this.bcvReferenceUsdCents,
    required this.hasRate,
    this.observedAt,
  });

  @override
  List<Object?> get props => [
    currency,
    nativeMinorAmount,
    realCostUsdCents,
    todayValueUsdCents,
    bcvReferenceUsdCents,
    hasRate,
    observedAt,
  ];
}

/// The Patrimonio engine's output (ADR-0016 §5): [todayValueUsdCents] and
/// [unrealizedPnlUsdCents] are computed with the parallel rate only;
/// [bcvReferenceUsdCents] is a labeled reference that never feeds either.
/// [hasMissingRate] flags the header as partial when any currency group
/// lacks a parallel observation.
class PatrimonioSnapshot extends Equatable {
  final int realCostUsdCents;
  final int todayValueUsdCents;
  final int unrealizedPnlUsdCents;
  final int bcvReferenceUsdCents;
  final bool hasMissingRate;
  final List<PatrimonioAccountGroup> accountGroups;
  final List<PatrimonioEnvelope> envelopes;

  const PatrimonioSnapshot({
    required this.realCostUsdCents,
    required this.todayValueUsdCents,
    required this.unrealizedPnlUsdCents,
    required this.bcvReferenceUsdCents,
    required this.hasMissingRate,
    required this.accountGroups,
    required this.envelopes,
  });

  factory PatrimonioSnapshot.empty() => const PatrimonioSnapshot(
    realCostUsdCents: 0,
    todayValueUsdCents: 0,
    unrealizedPnlUsdCents: 0,
    bcvReferenceUsdCents: 0,
    hasMissingRate: false,
    accountGroups: [],
    envelopes: [],
  );

  @override
  List<Object?> get props => [
    realCostUsdCents,
    todayValueUsdCents,
    unrealizedPnlUsdCents,
    bcvReferenceUsdCents,
    hasMissingRate,
    accountGroups,
    envelopes,
  ];
}

/// Informative metadata computed for one [PatrimonioEnvelope] from its
/// funding target (ADR-0015 — read-only, the cascade never reads it).
sealed class EnvelopeMetadata extends Equatable {
  const EnvelopeMetadata();
}

/// No funding target, or a degenerate one (e.g. a zero-amount Cap/GoalLine)
/// — nothing to project.
final class NoMetadata extends EnvelopeMetadata {
  const NoMetadata();

  @override
  List<Object?> get props => [];
}

/// Progress toward a [GoalLineView]. [progressPercent] is clamped to 100
/// once the balance meets or exceeds the goal (the real balance stays
/// visible on [PatrimonioEnvelope.balanceUsd]). [quotaPerMonthUsd] is the
/// suggested monthly contribution — 0 once fulfilled, overdue, or when no
/// [GoalLineView.dueDate] is set. [isOverdue] is true only when the due
/// date has strictly passed and the goal is still unfulfilled.
final class GoalLineMetadata extends EnvelopeMetadata {
  final int progressPercent;
  final int quotaPerMonthUsd;
  final int? daysRemaining;
  final bool isOverdue;
  final bool isFulfilled;

  const GoalLineMetadata({
    required this.progressPercent,
    required this.quotaPerMonthUsd,
    required this.daysRemaining,
    required this.isOverdue,
    required this.isFulfilled,
  });

  @override
  List<Object?> get props => [
    progressPercent,
    quotaPerMonthUsd,
    daysRemaining,
    isOverdue,
    isFulfilled,
  ];
}

/// Fill level of a [CapView]. [fillPercent] is clamped to 100 once
/// [isOverfilled] — the real balance stays visible on
/// [PatrimonioEnvelope.balanceUsd].
final class CapMetadata extends EnvelopeMetadata {
  final int fillPercent;
  final bool isOverfilled;

  const CapMetadata({required this.fillPercent, required this.isOverfilled});

  @override
  List<Object?> get props => [fillPercent, isOverfilled];
}

/// One Envelope in the Patrimonio snapshot (S2): a user Envelope with its
/// computed [metadata], or a system Envelope (Stage/Apertura) surfaced only
/// when it carries a non-zero balance — Diferencial/Ajustes never appear
/// (ADR-0015 §consequence: the four system Envelopes are role-identified).
class PatrimonioEnvelope extends Equatable {
  final EnvelopeId id;
  final String name;
  final EnvelopeRoleView role;
  final int balanceUsd;
  final FundingTargetView target;
  final EnvelopeMetadata metadata;
  final String? iconId;
  final int? colorIndex;

  const PatrimonioEnvelope({
    required this.id,
    required this.name,
    required this.role,
    required this.balanceUsd,
    required this.target,
    required this.metadata,
    this.iconId,
    this.colorIndex,
  });

  @override
  List<Object?> get props => [
    id,
    name,
    role,
    balanceUsd,
    target,
    metadata,
    iconId,
    colorIndex,
  ];
}
