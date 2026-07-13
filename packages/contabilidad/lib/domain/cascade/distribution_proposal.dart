import 'package:equatable/equatable.dart';
import 'package:shared_kernel/shared_kernel.dart';

class DistributionProposal extends Equatable {
  final CurrencyCode currency;
  final Map<EnvelopeId, Money> movements;

  DistributionProposal(this.currency, Map<EnvelopeId, Money> movements)
    : movements = Map.unmodifiable(movements);

  factory DistributionProposal.empty(CurrencyCode currency) =>
      DistributionProposal(currency, const {});

  bool get isEmpty => movements.isEmpty;

  Money? operator [](EnvelopeId envelopeId) => movements[envelopeId];

  Money total() => movements.values.fold(
    Money.zero(currency),
    (sum, movement) => sum.add(movement),
  );

  @override
  List<Object?> get props => [currency, movements];
}
