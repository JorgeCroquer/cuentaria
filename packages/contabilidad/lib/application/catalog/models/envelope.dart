import 'package:equatable/equatable.dart';
import 'package:shared_kernel/shared_kernel.dart';

import 'funding_target.dart';

enum EnvelopeRole { stage, differential, adjustments, opening, none }

class Envelope extends Equatable {
  final EnvelopeId id;
  final String name;
  final EnvelopeRole role;
  final bool isArchived;
  final DateTime updatedAt;
  final Map<String, dynamic>? meta;

  const Envelope({
    required this.id,
    required this.name,
    required this.role,
    required this.isArchived,
    required this.updatedAt,
    this.meta,
  });

  /// Typed funding target decoded from [meta].  Defaults to [NoTarget].
  FundingTarget get target {
    final raw = meta?['target'];
    if (raw == null) return const NoTarget();
    return FundingTarget.fromJson(raw as Map<String, dynamic>);
  }

  /// Returns a copy with [newTarget] encoded into [meta].
  ///
  /// Throws [ArgumentError] if [role] != [EnvelopeRole.none] — system
  /// envelopes must never carry a target (ADR-0015 C2-2).
  Envelope withTarget(FundingTarget newTarget) {
    if (role != EnvelopeRole.none) {
      throw ArgumentError(
        'Cannot set a target on a system envelope (role=$role)',
      );
    }
    final updated = Map<String, dynamic>.from(meta ?? {});
    if (newTarget is NoTarget) {
      updated.remove('target');
    } else {
      updated['target'] = newTarget.toJson();
    }
    return Envelope(
      id: id,
      name: name,
      role: role,
      isArchived: isArchived,
      updatedAt: updatedAt,
      meta: updated.isEmpty ? null : updated,
    );
  }

  /// Merges this envelope with another using Last-Write-Wins based on [updatedAt].
  /// If timestamps are exactly equal, the current instance is kept.
  /// The [role] is globally immutable and always preserved from the base instance.
  Envelope mergeWith(Envelope other) {
    if (id != other.id) {
      throw ArgumentError('Cannot merge envelopes with different IDs');
    }

    if (other.updatedAt.isAfter(updatedAt)) {
      return Envelope(
        id: id,
        name: other.name,
        role: role, // strictly preserves the original role
        isArchived: other.isArchived,
        updatedAt: other.updatedAt,
        meta: other.meta,
      );
    }
    return this;
  }

  @override
  List<Object?> get props => [id, name, role, isArchived, updatedAt, meta];
}
