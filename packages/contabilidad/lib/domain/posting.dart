import 'package:equatable/equatable.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'posting_target.dart';

class Posting extends Equatable {
  final PostingTarget target;
  final Money amountNative;
  final CurrencyCode currency;
  final int amountUsd;
  final String? rateRef;

  const Posting({
    required this.target,
    required this.amountNative,
    required this.currency,
    required this.amountUsd,
    this.rateRef,
  });

  Dimension get dimension => target.dimension;

  @override
  List<Object?> get props => [
    target,
    amountNative,
    currency,
    amountUsd,
    rateRef,
  ];
}
