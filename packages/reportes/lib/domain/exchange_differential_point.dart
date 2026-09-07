import 'report_month.dart';

/// One month's Diferencial cambiario (#264, ADR-0024 §7): [realizadoUsdCents]
/// is the month's flow into the Sobre de Sistema Diferencial (#259, always
/// present, $0 with no postings); [noRealizadoUsdCents] is the month-end Net
/// Worth Point's overlay gap (#260) — null, never zero, whenever that point
/// has no market value to compare against real cost.
class ExchangeDifferentialPoint {
  final ReportMonth month;
  final int realizadoUsdCents;
  final int? noRealizadoUsdCents;

  const ExchangeDifferentialPoint({
    required this.month,
    required this.realizadoUsdCents,
    this.noRealizadoUsdCents,
  });

  @override
  bool operator ==(Object other) =>
      other is ExchangeDifferentialPoint &&
      other.month == month &&
      other.realizadoUsdCents == realizadoUsdCents &&
      other.noRealizadoUsdCents == noRealizadoUsdCents;

  @override
  int get hashCode =>
      Object.hash(month, realizadoUsdCents, noRealizadoUsdCents);

  @override
  String toString() =>
      'ExchangeDifferentialPoint($month, realizado: $realizadoUsdCents, '
      'noRealizado: $noRealizadoUsdCents)';
}
