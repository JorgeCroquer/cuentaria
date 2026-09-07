/// A calendar month in local wall-clock time (ADR-0024 §4): the only unit
/// Reportes cuts time into — no "last 30 days", no free range.
class ReportMonth {
  ReportMonth(this.year, this.month)
    : assert(month >= 1 && month <= 12, 'month must be between 1 and 12');

  final int year;
  final int month;

  DateTime get startOfMonth => DateTime(year, month);

  DateTime get endOfMonth =>
      DateTime(year, month + 1).subtract(const Duration(microseconds: 1));

  int get daysInMonth =>
      DateTime(year, month + 1).difference(DateTime(year, month)).inDays;

  ReportMonth get previousMonth =>
      month == 1 ? ReportMonth(year - 1, 12) : ReportMonth(year, month - 1);

  ReportMonth get nextMonth =>
      month == 12 ? ReportMonth(year + 1, 1) : ReportMonth(year, month + 1);

  @override
  bool operator ==(Object other) =>
      other is ReportMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() => 'ReportMonth($year-$month)';
}
