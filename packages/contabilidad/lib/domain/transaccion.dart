import 'package:equatable/equatable.dart';
import 'package:event_bus/event_bus.dart';
import 'posting.dart';
import 'posting_target.dart';
import 'transaccion_metadata.dart';
import 'transaccion_error.dart';

class Transaccion extends DomainEvent with EquatableMixin {
  final List<Posting> postings;
  final TransaccionMetadata metadata;

  const Transaccion._({required this.postings, required this.metadata});

  factory Transaccion.crear({
    required List<Posting> postings,
    required TransaccionMetadata metadata,
  }) {
    if (postings.isEmpty) {
      throw TransaccionVacia();
    }

    int sumaCuentas = 0;
    int sumaSobres = 0;

    for (final posting in postings) {
      if (posting.dimension == Dimension.cuenta) {
        sumaCuentas += posting.amountUsd;
      } else if (posting.dimension == Dimension.sobre) {
        sumaSobres += posting.amountUsd;
      }
    }

    if (sumaCuentas != sumaSobres) {
      throw TransaccionNoBalanceada();
    }

    return Transaccion._(
      postings: List.unmodifiable(postings),
      metadata: metadata,
    );
  }

  @override
  List<Object?> get props => [postings, metadata];
}
