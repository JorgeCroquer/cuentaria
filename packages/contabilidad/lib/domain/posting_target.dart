import 'package:equatable/equatable.dart';
import 'package:shared_kernel/shared_kernel.dart';

enum Dimension { account, envelope }

sealed class PostingTarget extends Equatable {
  Dimension get dimension;
}

class AccountTarget extends PostingTarget {
  final AccountId accountId;
  AccountTarget(this.accountId);

  @override
  Dimension get dimension => Dimension.account;

  @override
  List<Object?> get props => [accountId];
}

class EnvelopeTarget extends PostingTarget {
  final EnvelopeId envelopeId;
  EnvelopeTarget(this.envelopeId);

  @override
  Dimension get dimension => Dimension.envelope;

  @override
  List<Object?> get props => [envelopeId];
}
