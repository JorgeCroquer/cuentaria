import 'package:contabilidad/application/cascade/cascade_engine.dart';
import 'package:contabilidad/domain/cascade/cascade.dart';
import 'package:contabilidad/domain/cascade/cascade_step.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:test/test.dart';

void main() {
  final usd = CurrencyCode('USD');
  final eur = CurrencyCode('EUR');

  Money money(int amount, [CurrencyCode? currency]) =>
      Money(amount: BigInt.from(amount), currency: currency ?? usd);

  final env1 = EnvelopeId('env-1');
  final env2 = EnvelopeId('env-2');
  final env3 = EnvelopeId('env-3');

  group('CascadeEngine.run', () {
    test(
      'single fixed step allocates fully when remaining >= target amount',
      () {
        final proposal = CascadeEngine.run(
          money(100),
          Cascade([CascadeStep.fixed(env1, money(50))]),
          {env1: money(100)},
        );

        expect(proposal[env1], money(50));
        expect(proposal.total(), money(50));
      },
    );

    test('multiple fixed steps clamp to remaining, in order', () {
      final proposal = CascadeEngine.run(
        money(100),
        Cascade([
          CascadeStep.fixed(env1, money(30)),
          CascadeStep.fixed(env2, money(50)),
          CascadeStep.fixed(env3, money(40)),
        ]),
        {env1: money(1000), env2: money(1000), env3: money(1000)},
      );

      expect(proposal[env1], money(30));
      expect(proposal[env2], money(50));
      expect(proposal[env3], money(20));
      expect(proposal.total(), money(100));
    });

    test(
      'lean month: top steps fund fully, exhausting step gets the rest, later steps get 0',
      () {
        final proposal = CascadeEngine.run(
          money(60),
          Cascade([
            CascadeStep.fixed(env1, money(30)),
            CascadeStep.fixed(env2, money(50)),
            CascadeStep.fixed(env3, money(10)),
          ]),
          {env1: money(1000), env2: money(1000), env3: money(1000)},
        );

        expect(proposal[env1], money(30));
        expect(proposal[env2], money(30));
        expect(proposal[env3], isNull);
        expect(proposal.total(), money(60));
      },
    );

    test('amount = 0 produces an empty proposal', () {
      final proposal = CascadeEngine.run(
        money(0),
        Cascade([CascadeStep.fixed(env1, money(100))]),
        {env1: money(100)},
      );

      expect(proposal.isEmpty, isTrue);
    });

    test('empty cascade produces an empty proposal', () {
      final proposal = CascadeEngine.run(
        money(100),
        Cascade(const []),
        const {},
      );

      expect(proposal.isEmpty, isTrue);
    });

    test(
      'a fixed step targeting an envelope missing from envelopeStates is skipped',
      () {
        final proposal = CascadeEngine.run(
          money(100),
          Cascade([CascadeStep.fixed(env1, money(100))]),
          const {},
        );

        expect(proposal.isEmpty, isTrue);
      },
    );

    test('a fixed step with a currency mismatched to amount is skipped', () {
      final proposal = CascadeEngine.run(
        money(100),
        Cascade([CascadeStep.fixed(env1, money(100, eur))]),
        {env1: money(100)},
      );

      expect(proposal.isEmpty, isTrue);
    });

    test('never throws for the skip scenarios combined', () {
      expect(
        () => CascadeEngine.run(
          money(0),
          Cascade([
            CascadeStep.fixed(env1, money(100, eur)),
            CascadeStep.fixed(env2, money(50)),
          ]),
          {env1: money(100)},
        ),
        returnsNormally,
      );
    });

    test(
      'proposal movements are never negative and total is never above amount (property)',
      () {
        final cases = [
          (money(0), <CascadeStep>[]),
          (money(10), [CascadeStep.fixed(env1, money(30))]),
          (
            money(75),
            [
              CascadeStep.fixed(env1, money(20)),
              CascadeStep.fixed(env2, money(20)),
              CascadeStep.fixed(env3, money(20)),
            ],
          ),
          (
            money(200),
            [
              CascadeStep.fixed(env1, money(30)),
              CascadeStep.fixed(env2, money(50, eur)),
              CascadeStep.fixed(env3, money(40)),
            ],
          ),
        ];
        final states = {
          env1: money(1000),
          env2: money(1000),
          env3: money(1000),
        };

        for (final (amount, steps) in cases) {
          final proposal = CascadeEngine.run(amount, Cascade(steps), states);

          for (final movement in proposal.movements.values) {
            expect(movement.amount.isNegative, isFalse);
          }
          expect(proposal.total().amount <= amount.amount, isTrue);
        }
      },
    );
  });
}
