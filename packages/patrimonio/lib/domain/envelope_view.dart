import 'package:equatable/equatable.dart';
import 'package:shared_kernel/shared_kernel.dart';

/// Patrimonio-owned mirror of contabilidad's `EnvelopeRole` (ADR-0005): a
/// context never imports another's `domain/`, so app-layer wiring maps
/// contabilidad's role enum into this one. `user` stands for contabilidad's
/// `none` (a regular, user-created Envelope).
enum EnvelopeRoleView { user, stage, differential, adjustments, opening }

/// Patrimonio-owned mirror of contabilidad's `FundingTarget` (ADR-0010):
/// `NoTarget | Cap | GoalLine`, read-only and informative (ADR-0015 — the
/// cascade never reads it).
sealed class FundingTargetView extends Equatable {
  const FundingTargetView();
}

final class NoTargetView extends FundingTargetView {
  const NoTargetView();

  @override
  List<Object?> get props => [];
}

final class CapView extends FundingTargetView {
  final int amountUsd;

  const CapView({required this.amountUsd});

  @override
  List<Object?> get props => [amountUsd];
}

final class GoalLineView extends FundingTargetView {
  final int amountUsd;
  final DateTime? dueDate;

  const GoalLineView({required this.amountUsd, this.dueDate});

  @override
  List<Object?> get props => [amountUsd, dueDate];
}

/// Patrimonio-owned read view of an Envelope (ADR-0005): the engine takes
/// only this — app-layer wiring maps contabilidad's Envelope + balance into
/// it before calling [PatrimonioEngine].
class EnvelopeView extends Equatable {
  final EnvelopeId id;
  final String name;
  final EnvelopeRoleView role;
  final int balanceUsd;
  final FundingTargetView target;

  const EnvelopeView({
    required this.id,
    required this.name,
    required this.role,
    required this.balanceUsd,
    required this.target,
  });

  @override
  List<Object?> get props => [id, name, role, balanceUsd, target];
}
