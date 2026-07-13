import 'package:equatable/equatable.dart';
import 'package:shared_kernel/shared_kernel.dart';

sealed class CascadeStep extends Equatable {
  const CascadeStep();

  factory CascadeStep.fixed(EnvelopeId target, Money amountUsd) =
      FixedCascadeStep;
}

class FixedCascadeStep extends CascadeStep {
  final EnvelopeId target;
  final Money amountUsd;

  const FixedCascadeStep(this.target, this.amountUsd);

  @override
  List<Object?> get props => [target, amountUsd];
}
