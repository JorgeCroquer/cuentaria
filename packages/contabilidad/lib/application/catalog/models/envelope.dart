import 'package:equatable/equatable.dart';
import 'package:shared_kernel/shared_kernel.dart';

enum EnvelopeRole {
  stage,
  diferencial,
  ajustes,
  apertura,
  ninguno,
}

class Envelope extends Equatable {
  final EnvelopeId id;
  final String name;
  final EnvelopeRole role;
  final bool isArchived;
  final DateTime updatedAt;

  const Envelope({
    required this.id,
    required this.name,
    required this.role,
    required this.isArchived,
    required this.updatedAt,
  });

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
      );
    }
    return this;
  }

  @override
  List<Object?> get props => [
        id,
        name,
        role,
        isArchived,
        updatedAt,
      ];
}
