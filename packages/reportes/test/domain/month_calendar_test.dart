import 'package:reportes/reportes.dart';
import 'package:test/test.dart';

void main() {
  group('MonthCalendar.getReportMonth', () {
    test(
      '23:30 Aug 31 in Caracas (UTC-4, 03:30 Sep 1 UTC) falls in August',
      () {
        final instantUtc = DateTime.utc(2026, 9, 1, 3, 30);
        const caracasOffset = Duration(hours: -4);

        final reportMonth = MonthCalendar.getReportMonth(
          instantUtc,
          caracasOffset,
        );

        expect(reportMonth, ReportMonth(2026, 8));
      },
    );

    test('returns the month start/end boundaries in local wall-clock time', () {
      final instantUtc = DateTime.utc(2026, 9, 1, 3, 30);
      const caracasOffset = Duration(hours: -4);

      final reportMonth = MonthCalendar.getReportMonth(
        instantUtc,
        caracasOffset,
      );

      expect(reportMonth.startOfMonth, DateTime(2026, 8, 1));
      expect(
        reportMonth.endOfMonth,
        DateTime(2026, 9).subtract(const Duration(microseconds: 1)),
      );
    });

    test('an instant that is still in September UTC lands in September', () {
      final instantUtc = DateTime.utc(2026, 9, 1, 5);
      const caracasOffset = Duration(hours: -4);

      final reportMonth = MonthCalendar.getReportMonth(
        instantUtc,
        caracasOffset,
      );

      expect(reportMonth, ReportMonth(2026, 9));
    });
  });

  group('ReportMonth.previousMonth', () {
    test('March 2026 → February 2026 with 28 days', () {
      final previous = ReportMonth(2026, 3).previousMonth;

      expect(previous, ReportMonth(2026, 2));
      expect(previous.daysInMonth, 28);
    });

    test('January 2026 → December 2025, crossing the year boundary', () {
      final previous = ReportMonth(2026, 1).previousMonth;

      expect(previous, ReportMonth(2025, 12));
    });
  });

  group('ReportMonth.nextMonth', () {
    test('December 2025 → January 2026, crossing the year boundary', () {
      final next = ReportMonth(2025, 12).nextMonth;

      expect(next, ReportMonth(2026, 1));
    });
  });
}
