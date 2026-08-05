import 'package:decimal/decimal.dart';
import 'package:test/test.dart';

import 'package:contabilidad/domain/reconciliation/reconciliation_planner.dart';

void main() {
  group('planReconciliation', () {
    // USD account: 1 native cent == 1 USD cent, so rate is always 1.
    final usdRate = Decimal.one;
    // Foreign account: 40 native minor units per USD.
    final foreignRate = Decimal.fromInt(40);

    test('delta zero on USD account is nothing to reconcile', () {
      final outcome = planReconciliation(
        deltaNative: BigInt.zero,
        rate: usdRate,
      );
      expect(outcome, isA<NothingToReconcile>());
    });

    test('delta zero on foreign account is nothing to reconcile', () {
      final outcome = planReconciliation(
        deltaNative: BigInt.zero,
        rate: foreignRate,
      );
      expect(outcome, isA<NothingToReconcile>());
    });

    test('small positive delta on USD account absorbs', () {
      final outcome = planReconciliation(
        deltaNative: BigInt.from(50),
        rate: usdRate,
      );
      expect(
        outcome,
        isA<Absorb>()
            .having((o) => o.deltaNative, 'deltaNative', BigInt.from(50))
            .having((o) => o.deltaUsd, 'deltaUsd', 50),
      );
    });

    test('small negative delta on USD account absorbs', () {
      final outcome = planReconciliation(
        deltaNative: BigInt.from(-50),
        rate: usdRate,
      );
      expect(
        outcome,
        isA<Absorb>()
            .having((o) => o.deltaNative, 'deltaNative', BigInt.from(-50))
            .having((o) => o.deltaUsd, 'deltaUsd', -50),
      );
    });

    test('large positive delta on USD account routes to income', () {
      final outcome = planReconciliation(
        deltaNative: BigInt.from(500),
        rate: usdRate,
      );
      expect(
        outcome,
        isA<RouteToIncome>()
            .having((o) => o.deltaNative, 'deltaNative', BigInt.from(500))
            .having((o) => o.suggestedUsd, 'suggestedUsd', 500),
      );
    });

    test('large negative delta on USD account routes to expense', () {
      final outcome = planReconciliation(
        deltaNative: BigInt.from(-500),
        rate: usdRate,
      );
      expect(
        outcome,
        isA<RouteToExpense>()
            .having((o) => o.deltaNative, 'deltaNative', BigInt.from(-500))
            .having((o) => o.suggestedUsd, 'suggestedUsd', -500),
      );
    });

    test('positive delta exactly at the tolerance threshold absorbs', () {
      final outcome = planReconciliation(
        deltaNative: BigInt.from(100),
        rate: usdRate,
      );
      expect(outcome, isA<Absorb>());
    });

    test('negative delta exactly at the tolerance threshold absorbs', () {
      final outcome = planReconciliation(
        deltaNative: BigInt.from(-100),
        rate: usdRate,
      );
      expect(outcome, isA<Absorb>());
    });

    test('small positive delta on foreign currency account absorbs', () {
      // 2000 minor units / 40 = 50 cents, under the $1 tolerance.
      final outcome = planReconciliation(
        deltaNative: BigInt.from(2000),
        rate: foreignRate,
      );
      expect(
        outcome,
        isA<Absorb>()
            .having((o) => o.deltaNative, 'deltaNative', BigInt.from(2000))
            .having((o) => o.deltaUsd, 'deltaUsd', 50),
      );
    });

    test('small negative delta on foreign currency account absorbs', () {
      final outcome = planReconciliation(
        deltaNative: BigInt.from(-2000),
        rate: foreignRate,
      );
      expect(
        outcome,
        isA<Absorb>()
            .having((o) => o.deltaNative, 'deltaNative', BigInt.from(-2000))
            .having((o) => o.deltaUsd, 'deltaUsd', -50),
      );
    });

    test(
      'large positive delta on foreign currency account routes to income',
      () {
        // 20000 minor units / 40 = 500 cents, over the $1 tolerance.
        final outcome = planReconciliation(
          deltaNative: BigInt.from(20000),
          rate: foreignRate,
        );
        expect(
          outcome,
          isA<RouteToIncome>()
              .having((o) => o.deltaNative, 'deltaNative', BigInt.from(20000))
              .having((o) => o.suggestedUsd, 'suggestedUsd', 500),
        );
      },
    );

    test(
      'large negative delta on foreign currency account routes to expense',
      () {
        final outcome = planReconciliation(
          deltaNative: BigInt.from(-20000),
          rate: foreignRate,
        );
        expect(
          outcome,
          isA<RouteToExpense>()
              .having((o) => o.deltaNative, 'deltaNative', BigInt.from(-20000))
              .having((o) => o.suggestedUsd, 'suggestedUsd', -500),
        );
      },
    );

    test('small native delta crosses the threshold once converted to USD '
        '(strong foreign currency)', () {
      // rate < 1: each native minor unit is worth more than a USD cent.
      final strongRate = Decimal.parse('0.1');
      // 50 native minor units / 0.1 = 500 cents, over the $1 tolerance.
      final outcome = planReconciliation(
        deltaNative: BigInt.from(50),
        rate: strongRate,
      );
      expect(outcome, isA<RouteToIncome>());
    });

    test('large native delta stays under tolerance once converted to USD '
        '(hyperinflated currency)', () {
      final hyperinflatedRate = Decimal.fromInt(1000000);
      // 50,000,000 / 1,000,000 = 50 cents, under the $1 tolerance.
      final outcome = planReconciliation(
        deltaNative: BigInt.from(50000000),
        rate: hyperinflatedRate,
      );
      expect(outcome, isA<Absorb>());
    });

    test('custom tolerance is respected', () {
      final outcome = planReconciliation(
        deltaNative: BigInt.from(150),
        rate: usdRate,
        toleranceUsdCents: 200,
      );
      expect(outcome, isA<Absorb>());
    });
  });
}
