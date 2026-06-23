import 'package:contabilidad/application/catalog/models/funding_target.dart';
import 'package:test/test.dart';

void main() {
  group('FundingTarget', () {
    group('NoTarget', () {
      test('default instance equality', () {
        expect(const NoTarget(), const NoTarget());
      });

      test('round-trips through JSON', () {
        const t = NoTarget();
        final json = t.toJson();
        expect(FundingTarget.fromJson(json), const NoTarget());
      });
    });

    group('Cap', () {
      test('stores cents as int', () {
        const t = Cap(amountUsd: 10000);
        expect(t.amountUsd, 10000);
      });

      test('equality', () {
        expect(const Cap(amountUsd: 5000), const Cap(amountUsd: 5000));
        expect(
          const Cap(amountUsd: 5000) == const Cap(amountUsd: 9999),
          isFalse,
        );
      });

      test('round-trips through JSON', () {
        const t = Cap(amountUsd: 30000);
        expect(FundingTarget.fromJson(t.toJson()), const Cap(amountUsd: 30000));
      });
    });

    group('GoalLine', () {
      test('stores cents and optional date', () {
        final due = DateTime.utc(2027, 12, 31);
        final t = GoalLine(amountUsd: 100000, dueDate: due);
        expect(t.amountUsd, 100000);
        expect(t.dueDate, due);
      });

      test('null dueDate allowed', () {
        const t = GoalLine(amountUsd: 50000);
        expect(t.dueDate, isNull);
      });

      test('equality — with date', () {
        final due = DateTime.utc(2027, 1, 1);
        expect(
          GoalLine(amountUsd: 50000, dueDate: due),
          GoalLine(amountUsd: 50000, dueDate: due),
        );
      });

      test('equality — no date', () {
        expect(
          const GoalLine(amountUsd: 50000),
          const GoalLine(amountUsd: 50000),
        );
      });

      test('round-trips through JSON with date', () {
        final t = GoalLine(amountUsd: 75000, dueDate: DateTime.utc(2028, 6, 1));
        expect(
          FundingTarget.fromJson(t.toJson()),
          GoalLine(amountUsd: 75000, dueDate: DateTime.utc(2028, 6, 1)),
        );
      });

      test('round-trips through JSON without date', () {
        const t = GoalLine(amountUsd: 75000);
        expect(
          FundingTarget.fromJson(t.toJson()),
          const GoalLine(amountUsd: 75000),
        );
      });
    });

    group('fromJson — invalid type throws', () {
      test('unknown type key throws FormatException', () {
        expect(
          () => FundingTarget.fromJson({'type': 'unknown'}),
          throwsFormatException,
        );
      });
    });
  });
}
