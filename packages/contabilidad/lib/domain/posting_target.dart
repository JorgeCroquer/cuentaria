import 'package:equatable/equatable.dart';
import 'package:shared_kernel/shared_kernel.dart';

enum Dimension { cuenta, sobre }

sealed class PostingTarget extends Equatable {
  Dimension get dimension;
}

class CuentaTarget extends PostingTarget {
  final AccountId accountId;
  CuentaTarget(this.accountId);

  @override
  Dimension get dimension => Dimension.cuenta;

  @override
  List<Object?> get props => [accountId];
}

class SobreTarget extends PostingTarget {
  final EnvelopeId envelopeId;
  SobreTarget(this.envelopeId);

  @override
  Dimension get dimension => Dimension.sobre;

  @override
  List<Object?> get props => [envelopeId];
}
