import 'report_month.dart';

/// One Net Worth Point (ADR-0024 §5-6): [month]'s ledger replayed to its
/// end, valued with the patrimonio engine. [marketValueUsdCents] is null
/// when at least one currency held that month has no rate observation on or
/// before its end — an honest gap, never a guess — while [realCostUsdCents]
/// (frozen cost, ADR-0006) is always present. [rateSource]/[rateObservedAt]
/// carry the parallel rate actually used when a value was computed, so the
/// UI can announce it even when it is older than the month itself.
class PatrimonioPoint {
  final ReportMonth month;
  final int realCostUsdCents;
  final int? marketValueUsdCents;
  final String? rateSource;
  final DateTime? rateObservedAt;

  const PatrimonioPoint({
    required this.month,
    required this.realCostUsdCents,
    this.marketValueUsdCents,
    this.rateSource,
    this.rateObservedAt,
  });

  @override
  bool operator ==(Object other) =>
      other is PatrimonioPoint &&
      other.month == month &&
      other.realCostUsdCents == realCostUsdCents &&
      other.marketValueUsdCents == marketValueUsdCents &&
      other.rateSource == rateSource &&
      other.rateObservedAt == rateObservedAt;

  @override
  int get hashCode => Object.hash(
    month,
    realCostUsdCents,
    marketValueUsdCents,
    rateSource,
    rateObservedAt,
  );

  @override
  String toString() =>
      'PatrimonioPoint($month, realCost: $realCostUsdCents, '
      'marketValue: $marketValueUsdCents)';
}
