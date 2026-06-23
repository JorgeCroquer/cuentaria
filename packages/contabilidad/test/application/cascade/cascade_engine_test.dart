import 'package:decimal/decimal.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:contabilidad/application/cascade/cascade_engine.dart';
import 'package:contabilidad/application/cascade/cascade_step.dart';
import 'package:contabilidad/application/cascade/distribution_proposal.dart';
import 'package:contabilidad/application/cascade/envelope_state.dart';
import 'package:test/test.dart';

void main() {
  final e1 = EnvelopeId('e1');
  final e2 = EnvelopeId('e2');
  final e3 = EnvelopeId('e3');

  EnvelopeState state({int balance = 0, int? cap}) =>
      EnvelopeState(balanceUsd: balance, capUsd: cap);

  List<AllocationLine> run(
    int amount,
    List<CascadeStep> steps, {
    Map<EnvelopeId, EnvelopeState> states = const {},
  }) =>
      CascadeEngine.run(amount: amount, steps: steps, envelopeStates: states)
          .allocations;

  // ─── fixed step ───────────────────────────────────────────────────────────
  group('fixed', () {
    test('assigns exactly F when remaining >= F', () {
      final result = run(
        500,
        [CascadeStep.fixed(envelopeId: e1, amountUsd: 200)],
        states: {e1: state()},
      );
      expect(result.single.amountUsd, 200);
      expect(result.single.envelopeId, e1);
    });

    test('clamps to remaining in lean month', () {
      final result = run(
        50,
        [CascadeStep.fixed(envelopeId: e1, amountUsd: 200)],
        states: {e1: state()},
      );
      expect(result.single.amountUsd, 50);
    });

    test('gives 0 when remaining == 0 (pure lean)', () {
      final result = run(
        0,
        [CascadeStep.fixed(envelopeId: e1, amountUsd: 200)],
        states: {e1: state()},
      );
      expect(result.single.amountUsd, 0);
    });
  });

  // ─── fillToCap step ───────────────────────────────────────────────────────
  group('fillToCap', () {
    test('fills deficit (cap - balance)', () {
      final result = run(
        500,
        [CascadeStep.fillToCap(envelopeId: e1)],
        states: {e1: state(balance: 60, cap: 150)},
      );
      expect(result.single.amountUsd, 90);
    });

    test('gives 0 when balance already at cap', () {
      final result = run(
        500,
        [CascadeStep.fillToCap(envelopeId: e1)],
        states: {e1: state(balance: 150, cap: 150)},
      );
      expect(result.single.amountUsd, 0);
    });

    test('gives 0 when balance above cap', () {
      final result = run(
        500,
        [CascadeStep.fillToCap(envelopeId: e1)],
        states: {e1: state(balance: 200, cap: 150)},
      );
      expect(result.single.amountUsd, 0);
    });

    test('gives 0 when envelope has no cap (total engine — never throws)', () {
      final result = run(
        500,
        [CascadeStep.fillToCap(envelopeId: e1)],
        states: {e1: state(balance: 0)}, // no cap
      );
      expect(result.single.amountUsd, 0);
    });

    test('clamps to remaining', () {
      final result = run(
        30,
        [CascadeStep.fillToCap(envelopeId: e1)],
        states: {e1: state(balance: 0, cap: 150)},
      );
      expect(result.single.amountUsd, 30);
    });
  });

  // ─── percentOfRemainder step ──────────────────────────────────────────────
  group('percentOfRemainder', () {
    test('base=remainder uses remaining counter', () {
      // 500 - 200(fixed) = 300 remaining; 30% of 300 = 90
      final result = run(
        500,
        [
          CascadeStep.fixed(envelopeId: e1, amountUsd: 200),
          CascadeStep.percentOfRemainder(
            envelopeId: e2,
            percent: Decimal.parse('0.30'),
            base: PercentBase.remainder,
          ),
        ],
        states: {e1: state(), e2: state()},
      );
      expect(result[1].amountUsd, 90);
    });

    test('base=gross uses original amount', () {
      // 30% of 500 = 150, regardless of prior steps
      final result = run(
        500,
        [
          CascadeStep.fixed(envelopeId: e1, amountUsd: 200),
          CascadeStep.percentOfRemainder(
            envelopeId: e2,
            percent: Decimal.parse('0.30'),
            base: PercentBase.gross,
          ),
        ],
        states: {e1: state(), e2: state()},
      );
      expect(result[1].amountUsd, 150);
    });

    test('base=gross clamps to remaining', () {
      // 500 - 400(fixed) = 100 remaining; 30% of 500 = 150 -> clamped to 100
      final result = run(
        500,
        [
          CascadeStep.fixed(envelopeId: e1, amountUsd: 400),
          CascadeStep.percentOfRemainder(
            envelopeId: e2,
            percent: Decimal.parse('0.30'),
            base: PercentBase.gross,
          ),
        ],
        states: {e1: state(), e2: state()},
      );
      expect(result[1].amountUsd, 100);
    });

    test('rounds to nearest integer (no doubles in result)', () {
      // 10% of 333 = 33.3 -> rounds to 33
      final result = run(
        333,
        [
          CascadeStep.percentOfRemainder(
            envelopeId: e1,
            percent: Decimal.parse('0.10'),
            base: PercentBase.remainder,
          ),
        ],
        states: {e1: state()},
      );
      expect(result.single.amountUsd, 33); // round(33.3)
    });
  });

  // ─── catchAll step ────────────────────────────────────────────────────────
  group('catchAll', () {
    test('absorbs all remaining', () {
      // 500 - 200 = 300 remaining -> catch-all gets 300
      final result = run(
        500,
        [
          CascadeStep.fixed(envelopeId: e1, amountUsd: 200),
          CascadeStep.catchAll(envelopeId: e2),
        ],
        states: {e1: state(), e2: state()},
      );
      expect(result[1].amountUsd, 300);
    });

    test('absorbs rounding residue to make proposal sum == amount', () {
      final result = run(
        333,
        [
          CascadeStep.fixed(envelopeId: e1, amountUsd: 100),
          CascadeStep.percentOfRemainder(
            envelopeId: e2,
            percent: Decimal.parse('0.30'),
            base: PercentBase.remainder,
          ),
          CascadeStep.catchAll(envelopeId: e3),
        ],
        states: {e1: state(), e2: state(), e3: state()},
      );
      final total = result.fold(0, (s, l) => s + l.amountUsd);
      expect(total, 333);
    });

    test('misplaced catch-all leaves later steps with 0', () {
      // catchAll first -> remaining=0 -> fixed gets 0
      final result = run(
        500,
        [
          CascadeStep.catchAll(envelopeId: e1),
          CascadeStep.fixed(envelopeId: e2, amountUsd: 200),
        ],
        states: {e1: state(), e2: state()},
      );
      expect(result[0].amountUsd, 500);
      expect(result[1].amountUsd, 0);
    });
  });

  // ─── degradation (total engine) ────────────────────────────────────────────
  group('total engine — never throws', () {
    test('missing envelope state skips step', () {
      final result = run(
        500,
        [
          CascadeStep.fixed(envelopeId: e1, amountUsd: 200),
          CascadeStep.fixed(envelopeId: e2, amountUsd: 100), // e2 missing
          CascadeStep.catchAll(envelopeId: e3),
        ],
        states: {e1: state(), e3: state()}, // e2 absent
      );
      final ids = result.map((l) => l.envelopeId).toList();
      expect(ids, isNot(contains(e2)));
      // remaining after e1(200) = 300; e2 skipped; catchAll gets 300
      expect(result.firstWhere((l) => l.envelopeId == e3).amountUsd, 300);
    });

    test('fillToCap without cap gives 0 (total engine)', () {
      final result = run(
        500,
        [CascadeStep.fillToCap(envelopeId: e1)],
        states: {e1: state(balance: 0)}, // no cap
      );
      expect(result.single.amountUsd, 0);
    });
  });

  // ─── skip (filtered list) ─────────────────────────────────────────────────
  group('skip', () {
    test('running with filtered steps honours skip', () {
      final result = run(
        500,
        [
          CascadeStep.fixed(envelopeId: e1, amountUsd: 200),
          // e2 step skipped by caller — not included
          CascadeStep.catchAll(envelopeId: e3),
        ],
        states: {e1: state(), e3: state()},
      );
      expect(result.firstWhere((l) => l.envelopeId == e1).amountUsd, 200);
      expect(result.firstWhere((l) => l.envelopeId == e3).amountUsd, 300);
    });
  });

  // ─── edge cases ───────────────────────────────────────────────────────────
  group('edge cases', () {
    test('empty cascade returns empty proposal', () {
      final result = run(500, [], states: {});
      expect(result, isEmpty);
    });

    test('amount=0 all steps get 0', () {
      final result = run(
        0,
        [
          CascadeStep.fixed(envelopeId: e1, amountUsd: 200),
          CascadeStep.catchAll(envelopeId: e2),
        ],
        states: {e1: state(), e2: state()},
      );
      expect(result.every((l) => l.amountUsd == 0), isTrue);
    });

    test('residue stays in Stage when no catch-all — sum < amount', () {
      final result = run(
        500,
        [CascadeStep.fixed(envelopeId: e1, amountUsd: 200)],
        states: {e1: state()},
      );
      final total = result.fold(0, (s, l) => s + l.amountUsd);
      expect(total, 200);
    });
  });

  // ─── property tests ───────────────────────────────────────────────────────
  group('properties', () {
    test('never produces negative allocations for arbitrary inputs', () {
      final scenarios = [
        (100, [CascadeStep.fixed(envelopeId: e1, amountUsd: 200)]),
        (
          0,
          [
            CascadeStep.percentOfRemainder(
              envelopeId: e1,
              percent: Decimal.parse('0.5'),
              base: PercentBase.remainder,
            ),
          ],
        ),
        (
          999,
          [
            CascadeStep.fillToCap(envelopeId: e1),
            CascadeStep.catchAll(envelopeId: e2),
          ],
        ),
      ];
      for (final (amount, steps) in scenarios) {
        final result = run(
          amount,
          steps,
          states: {e1: state(balance: 0, cap: 50), e2: state()},
        );
        for (final line in result) {
          expect(line.amountUsd, greaterThanOrEqualTo(0),
              reason: 'negative in scenario amount=$amount');
        }
      }
    });

    test('sum <= amount always', () {
      for (final amount in [0, 1, 100, 999, 10000]) {
        final result = run(
          amount,
          [
            CascadeStep.fixed(envelopeId: e1, amountUsd: 300),
            CascadeStep.percentOfRemainder(
              envelopeId: e2,
              percent: Decimal.parse('0.5'),
              base: PercentBase.remainder,
            ),
          ],
          states: {e1: state(), e2: state()},
        );
        final total = result.fold(0, (s, l) => s + l.amountUsd);
        expect(total, lessThanOrEqualTo(amount),
            reason: 'sum > amount for amount=$amount');
      }
    });

    test('sum == amount when catch-all present', () {
      for (final amount in [0, 1, 100, 333, 10000]) {
        final result = run(
          amount,
          [
            CascadeStep.fixed(envelopeId: e1, amountUsd: 100),
            CascadeStep.percentOfRemainder(
              envelopeId: e2,
              percent: Decimal.parse('0.30'),
              base: PercentBase.remainder,
            ),
            CascadeStep.catchAll(envelopeId: e3),
          ],
          states: {e1: state(), e2: state(), e3: state()},
        );
        final total = result.fold(0, (s, l) => s + l.amountUsd);
        expect(total, amount,
            reason: 'sum != amount for amount=$amount with catch-all');
      }
    });
  });
}
