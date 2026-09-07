import 'report_month.dart';

/// Cuts a UTC instant into its [ReportMonth] using the device's local UTC
/// offset (ADR-0024 §4) — the only place in the system that cuts months, so
/// a 10pm expense on the 31st never lands in the following month just
/// because it was stored in UTC.
class MonthCalendar {
  const MonthCalendar._();

  static ReportMonth getReportMonth(DateTime instantUtc, Duration localOffset) {
    final local = instantUtc.toUtc().add(localOffset);
    return ReportMonth(local.year, local.month);
  }
}
