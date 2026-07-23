import 'package:equatable/equatable.dart';
import 'package:shared_kernel/shared_kernel.dart';

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

  const PatrimonioSnapshot({
    required this.realCostUsdCents,
    required this.todayValueUsdCents,
    required this.unrealizedPnlUsdCents,
    required this.bcvReferenceUsdCents,
    required this.hasMissingRate,
    required this.accountGroups,
  });

  factory PatrimonioSnapshot.empty() => const PatrimonioSnapshot(
    realCostUsdCents: 0,
    todayValueUsdCents: 0,
    unrealizedPnlUsdCents: 0,
    bcvReferenceUsdCents: 0,
    hasMissingRate: false,
    accountGroups: [],
  );

  @override
  List<Object?> get props => [
    realCostUsdCents,
    todayValueUsdCents,
    unrealizedPnlUsdCents,
    bcvReferenceUsdCents,
    hasMissingRate,
    accountGroups,
  ];
}
