import 'package:equatable/equatable.dart';

/// Reportes-owned mirror of contabilidad's `FundingTarget` (ADR-0005): a
/// context never imports another's `domain/`, so app-layer wiring maps
/// contabilidad's sealed `FundingTarget` into this one — the same pattern
/// `patrimonio` already uses for its own `FundingTargetView`.
sealed class FundingTargetView extends Equatable {
  const FundingTargetView();
}

/// No funding target — [FundingPaceEngine] skips envelopes carrying this.
final class NoTargetView extends FundingTargetView {
  const NoTargetView();

  @override
  List<Object?> get props => [];
}

/// A spending cap: never carries a due date, so [FundingPaceEngine] only
/// ever reports what was contributed this month for it.
final class CapView extends FundingTargetView {
  final int amountUsd;

  const CapView({required this.amountUsd});

  @override
  List<Object?> get props => [amountUsd];
}

/// A savings goal of [amountUsd] cents by optional [dueDate].
final class GoalLineView extends FundingTargetView {
  final int amountUsd;
  final DateTime? dueDate;

  const GoalLineView({required this.amountUsd, this.dueDate});

  @override
  List<Object?> get props => [amountUsd, dueDate];
}
