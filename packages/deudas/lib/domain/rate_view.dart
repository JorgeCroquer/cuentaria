import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';
import 'package:shared_kernel/shared_kernel.dart';

/// One captured parallel rate observation (S2-8: "the parallel values") —
/// how many native units are worth one USD, when that was observed, and
/// which source it came from, so the UI can announce it instead of hiding it.
class RateObservationView extends Equatable {
  final Decimal nativePerUsd;
  final DateTime observedAt;
  final String source;

  const RateObservationView({
    required this.nativePerUsd,
    required this.observedAt,
    required this.source,
  });

  @override
  List<Object?> get props => [nativePerUsd, observedAt, source];
}

/// Deudas-owned read view of a currency's known parallel rate. Absent when
/// no observation has been captured yet.
class RateView extends Equatable {
  final CurrencyCode currency;
  final RateObservationView? parallel;

  const RateView({required this.currency, this.parallel});

  @override
  List<Object?> get props => [currency, parallel];
}
