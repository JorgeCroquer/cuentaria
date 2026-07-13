import 'package:contabilidad/domain/cascade/cascade.dart';
import 'package:contabilidad/domain/cascade/cascade_step.dart';
import 'package:contabilidad/domain/cascade/distribution_proposal.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:test/test.dart';

void main() {
  final usd = CurrencyCode('USD');

  group('CascadeStep.fixed', () {
    test('creates an immutable VO with target and amountUsd', () {
      final target = EnvelopeId('env-1');
      final amount = Money(amount: BigInt.from(50), currency: usd);

      final step = CascadeStep.fixed(target, amount) as FixedCascadeStep;

      expect(step.target, target);
      expect(step.amountUsd, amount);
    });

    test('two fixed steps with equal fields are equal', () {
      final target = EnvelopeId('env-1');
      final amount = Money(amount: BigInt.from(50), currency: usd);

      expect(
        CascadeStep.fixed(target, amount),
        CascadeStep.fixed(target, amount),
      );
    });
  });

  group('Cascade', () {
    test('can be empty', () {
      final cascade = Cascade(const []);
      expect(cascade.steps, isEmpty);
    });

    test('preserves step order', () {
      final env1 = EnvelopeId('env-1');
      final env2 = EnvelopeId('env-2');
      final step1 = CascadeStep.fixed(
        env1,
        Money(amount: BigInt.from(10), currency: usd),
      );
      final step2 = CascadeStep.fixed(
        env2,
        Money(amount: BigInt.from(20), currency: usd),
      );

      final cascade = Cascade([step1, step2]);

      expect(cascade.steps, [step1, step2]);
    });
  });

  group('DistributionProposal', () {
    test('can be empty', () {
      final proposal = DistributionProposal.empty(usd);
      expect(proposal.isEmpty, isTrue);
      expect(proposal.total(), Money.zero(usd));
    });

    test('sums movements correctly', () {
      final env1 = EnvelopeId('env-1');
      final env2 = EnvelopeId('env-2');
      final proposal = DistributionProposal(usd, {
        env1: Money(amount: BigInt.from(30), currency: usd),
        env2: Money(amount: BigInt.from(20), currency: usd),
      });

      expect(proposal.total(), Money(amount: BigInt.from(50), currency: usd));
      expect(proposal[env1], Money(amount: BigInt.from(30), currency: usd));
    });
  });
}
