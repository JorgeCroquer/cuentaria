import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';
import 'package:shared_kernel/shared_kernel.dart';

/// One captured side of a currency's rate (ADR-0016): how many native units
/// are worth one USD, and when that was observed — exposed so the UI can
/// show staleness instead of hiding it.
class RateObservationView extends Equatable {
  final Decimal nativePerUsd;
  final DateTime observedAt;

  const RateObservationView({
    required this.nativePerUsd,
    required this.observedAt,
  });

  @override
  List<Object?> get props => [nativePerUsd, observedAt];
}

/// Patrimonio-owned read view of a currency's known rates. [parallel] values
/// net worth and unrealized P&L; [bcv] is only a labeled reference — it
/// never enters those totals (ADR-0016 §5). Either may be absent when no
/// observation has been captured yet.
class RateView extends Equatable {
  final CurrencyCode currency;
  final RateObservationView? parallel;
  final RateObservationView? bcv;

  const RateView({required this.currency, this.parallel, this.bcv});

  @override
  List<Object?> get props => [currency, parallel, bcv];
}
