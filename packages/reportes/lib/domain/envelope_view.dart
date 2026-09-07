import 'package:equatable/equatable.dart';
import 'package:shared_kernel/shared_kernel.dart';

/// Reportes-owned mirror of contabilidad's `EnvelopeRole` (ADR-0005): a
/// context never imports another's `domain/`, so app-layer wiring maps
/// contabilidad's role enum into this one. `user` stands for contabilidad's
/// `none` (a regular, user-created Envelope).
enum EnvelopeRoleView { user, stage, differential, adjustments, opening }

/// Reportes-owned read view of an Envelope (ADR-0005): the engine takes only
/// this — app-layer wiring maps contabilidad's Envelope into it beforehand.
class EnvelopeView extends Equatable {
  final EnvelopeId id;
  final String name;
  final EnvelopeRoleView role;

  const EnvelopeView({
    required this.id,
    required this.name,
    required this.role,
  });

  @override
  List<Object?> get props => [id, name, role];
}
