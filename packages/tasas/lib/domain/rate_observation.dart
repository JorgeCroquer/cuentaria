import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';
import 'package:shared_kernel/shared_kernel.dart';

/// An observed exchange rate fact (ADR-0016): [nativePerUsd] is how many
/// units of [currency] are worth one USD, e.g. a VES observation of 37.5
/// means 1 USD = 37.5 VES.
///
/// Append-only (ADR-0002): observations are never edited or deleted; a
/// correction is a new observation. [source] distinguishes provenance
/// (e.g. `manual:bcv`, `manual:paralelo`) and defaults to `manual`.
class RateObservation extends Equatable {
  final CurrencyCode currency;
  final Decimal nativePerUsd;
  final DateTime observedAt;
  final String source;

  RateObservation({
    required this.currency,
    required this.nativePerUsd,
    required this.observedAt,
    this.source = 'manual',
  });

  @override
  List<Object?> get props => [currency, nativePerUsd, observedAt, source];
}
