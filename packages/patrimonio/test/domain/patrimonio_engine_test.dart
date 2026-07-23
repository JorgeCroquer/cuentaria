import 'package:decimal/decimal.dart';
import 'package:patrimonio/domain/account_view.dart';
import 'package:patrimonio/domain/envelope_view.dart';
import 'package:patrimonio/domain/patrimonio_engine.dart';
import 'package:patrimonio/domain/patrimonio_snapshot.dart';
import 'package:patrimonio/domain/rate_view.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:test/test.dart';

void main() {
  const engine = PatrimonioEngine();
  final ves = CurrencyCode('VES');
  final usd = CurrencyCode('USD');
  final observedAt = DateTime.utc(2026, 7, 23);

  AccountView vesAccount({
    String id = 'acc-1',
    required BigInt native,
    required int realCostUsdCents,
    bool isArchived = false,
  }) => AccountView(
    id: AccountId(id),
    currency: ves,
    nativeMinorAmount: native,
    realCostUsdCents: realCostUsdCents,
    isArchived: isArchived,
  );

  group('PatrimonioEngine', () {
    test('canonical case: cost \$100 at executed 75, parallel 100 -> today '
        '\$75 / P&L -\$25, BCV 50 -> reference \$150', () {
      // Executed 75 Bs/USD on a $100 cost => native balance 7500 Bs
      // (750000 in minor units, matching the USD cents scale).
      final account = vesAccount(
        native: BigInt.from(750000),
        realCostUsdCents: 10000,
      );
      final rates = {
        ves: RateView(
          currency: ves,
          parallel: RateObservationView(
            nativePerUsd: Decimal.parse('100'),
            observedAt: observedAt,
          ),
          bcv: RateObservationView(
            nativePerUsd: Decimal.parse('50'),
            observedAt: observedAt,
          ),
        ),
      };

      final snapshot = engine([account], rates, const [], observedAt);

      expect(snapshot.realCostUsdCents, 10000);
      expect(snapshot.todayValueUsdCents, 7500);
      expect(snapshot.unrealizedPnlUsdCents, -2500);
      expect(snapshot.bcvReferenceUsdCents, 15000);
      expect(snapshot.hasMissingRate, isFalse);

      final group = snapshot.accountGroups.single;
      expect(group.currency, ves);
      expect(group.hasRate, isTrue);
      expect(group.observedAt, observedAt);
    });

    test('missing rate: currency without an observation falls back to real '
        'cost and is flagged, never a silent 1:1', () {
      final account = vesAccount(
        native: BigInt.from(750000),
        realCostUsdCents: 10000,
      );

      final snapshot = engine([account], const {}, const [], observedAt);

      expect(snapshot.realCostUsdCents, 10000);
      expect(snapshot.todayValueUsdCents, 10000);
      expect(snapshot.bcvReferenceUsdCents, 10000);
      expect(snapshot.unrealizedPnlUsdCents, 0);
      expect(snapshot.hasMissingRate, isTrue);
      expect(snapshot.accountGroups.single.hasRate, isFalse);
    });

    test('stale rate date: the observation date is exposed as-is', () {
      final longAgo = DateTime.utc(2020, 1, 1);
      final account = vesAccount(
        native: BigInt.from(750000),
        realCostUsdCents: 10000,
      );
      final rates = {
        ves: RateView(
          currency: ves,
          parallel: RateObservationView(
            nativePerUsd: Decimal.parse('100'),
            observedAt: longAgo,
          ),
        ),
      };

      final snapshot = engine([account], rates, const [], observedAt);

      expect(snapshot.accountGroups.single.observedAt, longAgo);
    });

    test('archived accounts are excluded from every total', () {
      final live = vesAccount(
        id: 'acc-live',
        native: BigInt.from(750000),
        realCostUsdCents: 10000,
      );
      final archived = vesAccount(
        id: 'acc-archived',
        native: BigInt.from(999999),
        realCostUsdCents: 99999,
        isArchived: true,
      );
      final rates = {
        ves: RateView(
          currency: ves,
          parallel: RateObservationView(
            nativePerUsd: Decimal.parse('100'),
            observedAt: observedAt,
          ),
        ),
      };

      final snapshot = engine([live, archived], rates, const [], observedAt);

      expect(snapshot.realCostUsdCents, 10000);
      expect(snapshot.accountGroups.single.realCostUsdCents, 10000);
    });

    test('empty catalog produces a zeroed snapshot with no groups', () {
      final snapshot = engine(const [], const {}, const [], observedAt);

      expect(snapshot.realCostUsdCents, 0);
      expect(snapshot.todayValueUsdCents, 0);
      expect(snapshot.unrealizedPnlUsdCents, 0);
      expect(snapshot.bcvReferenceUsdCents, 0);
      expect(snapshot.hasMissingRate, isFalse);
      expect(snapshot.accountGroups, isEmpty);
    });

    test('USD accounts bypass rates entirely, valuing at par with no '
        'observation needed', () {
      final account = AccountView(
        id: AccountId('acc-usd'),
        currency: usd,
        nativeMinorAmount: BigInt.from(2500),
        realCostUsdCents: 2500,
        isArchived: false,
      );

      final snapshot = engine([account], const {}, const [], observedAt);

      expect(snapshot.realCostUsdCents, 2500);
      expect(snapshot.todayValueUsdCents, 2500);
      expect(snapshot.bcvReferenceUsdCents, 2500);
      expect(snapshot.hasMissingRate, isFalse);
      expect(snapshot.accountGroups.single.hasRate, isTrue);
    });

    test('single rounding per account: native/rate rounds once, half away '
        'from zero', () {
      final account = vesAccount(
        native: BigInt.from(100001),
        realCostUsdCents: 1,
      );
      final rates = {
        ves: RateView(
          currency: ves,
          parallel: RateObservationView(
            nativePerUsd: Decimal.parse('3'),
            observedAt: observedAt,
          ),
        ),
      };

      final snapshot = engine([account], rates, const [], observedAt);

      // 100001 / 3 = 33333.67 -> rounds to 33334.
      expect(snapshot.todayValueUsdCents, 33334);
    });
  });

  group('PatrimonioEngine envelopes', () {
    final today = DateTime.utc(2026, 7, 23);

    EnvelopeView userEnvelope({
      String id = 'env-1',
      String name = 'Vacaciones',
      required int balanceUsd,
      FundingTargetView target = const NoTargetView(),
    }) => EnvelopeView(
      id: EnvelopeId(id),
      name: name,
      role: EnvelopeRoleView.user,
      balanceUsd: balanceUsd,
      target: target,
    );

    PatrimonioEnvelope run(EnvelopeView envelope) {
      final snapshot = engine(const [], const {}, [envelope], today);
      return snapshot.envelopes.single;
    }

    test('no target: balance only, no metadata beyond NoMetadata', () {
      final result = run(userEnvelope(balanceUsd: 4200));

      expect(result.balanceUsd, 4200);
      expect(result.metadata, const NoMetadata());
    });

    test('goal line in progress: quota rounds up over the remaining '
        'calendar months', () {
      final result = run(
        userEnvelope(
          balanceUsd: 4000,
          target: GoalLineView(
            amountUsd: 10000,
            dueDate: today.add(const Duration(days: 90)),
          ),
        ),
      );

      final metadata = result.metadata as GoalLineMetadata;
      expect(metadata.progressPercent, 40);
      expect(metadata.daysRemaining, 90);
      // 90 days -> 3 calendar months; (10000 - 4000) / 3 = 2000 exactly.
      expect(metadata.quotaPerMonthUsd, 2000);
      expect(metadata.isOverdue, isFalse);
      expect(metadata.isFulfilled, isFalse);
    });

    test('goal line quota rounds up to whole USD on an inexact split', () {
      final result = run(
        userEnvelope(
          balanceUsd: 0,
          target: GoalLineView(
            amountUsd: 1000,
            dueDate: today.add(const Duration(days: 61)),
          ),
        ),
      );

      final metadata = result.metadata as GoalLineMetadata;
      // 61 days -> ceil(61/30) = 3 months; ceil(1000/3) = 334.
      expect(metadata.quotaPerMonthUsd, 334);
    });

    test('goal line with less than a month left still uses a 1-month '
        'minimum', () {
      final result = run(
        userEnvelope(
          balanceUsd: 100,
          target: GoalLineView(
            amountUsd: 1000,
            dueDate: today.add(const Duration(days: 5)),
          ),
        ),
      );

      final metadata = result.metadata as GoalLineMetadata;
      expect(metadata.daysRemaining, 5);
      expect(metadata.quotaPerMonthUsd, 900);
    });

    test('goal line due today: 0 days remaining, quota still computes with '
        'the 1-month minimum', () {
      final result = run(
        userEnvelope(
          balanceUsd: 0,
          target: GoalLineView(amountUsd: 1000, dueDate: today),
        ),
      );

      final metadata = result.metadata as GoalLineMetadata;
      expect(metadata.daysRemaining, 0);
      expect(metadata.isOverdue, isFalse);
      expect(metadata.quotaPerMonthUsd, 1000);
    });

    test(
      'goal line fulfilled exactly at the goal: 100% progress, no quota',
      () {
        final result = run(
          userEnvelope(
            balanceUsd: 5000,
            target: const GoalLineView(amountUsd: 5000),
          ),
        );

        final metadata = result.metadata as GoalLineMetadata;
        expect(metadata.progressPercent, 100);
        expect(metadata.quotaPerMonthUsd, 0);
        expect(metadata.isFulfilled, isTrue);
      },
    );

    test('goal line exceeded: 100% progress but the real balance stays '
        'visible', () {
      final result = run(
        userEnvelope(
          balanceUsd: 7000,
          target: const GoalLineView(amountUsd: 5000),
        ),
      );

      expect(result.balanceUsd, 7000);
      final metadata = result.metadata as GoalLineMetadata;
      expect(metadata.progressPercent, 100);
      expect(metadata.quotaPerMonthUsd, 0);
      expect(metadata.isFulfilled, isTrue);
    });

    test('goal line overdue and unfulfilled: flagged, no quota', () {
      final result = run(
        userEnvelope(
          balanceUsd: 3000,
          target: GoalLineView(
            amountUsd: 10000,
            dueDate: today.subtract(const Duration(days: 10)),
          ),
        ),
      );

      final metadata = result.metadata as GoalLineMetadata;
      expect(metadata.isOverdue, isTrue);
      expect(metadata.quotaPerMonthUsd, 0);
      expect(metadata.isFulfilled, isFalse);
    });

    test('cap under the limit: fill level below 100, not overfilled', () {
      final result = run(
        userEnvelope(balanceUsd: 2000, target: const CapView(amountUsd: 5000)),
      );

      final metadata = result.metadata as CapMetadata;
      expect(metadata.fillPercent, 40);
      expect(metadata.isOverfilled, isFalse);
    });

    test('cap exactly at the limit: 100% fill, not overfilled', () {
      final result = run(
        userEnvelope(balanceUsd: 5000, target: const CapView(amountUsd: 5000)),
      );

      final metadata = result.metadata as CapMetadata;
      expect(metadata.fillPercent, 100);
      expect(metadata.isOverfilled, isFalse);
    });

    test(
      'cap overfilled: 100% fill, overfilled flag, real balance visible',
      () {
        final result = run(
          userEnvelope(
            balanceUsd: 6000,
            target: const CapView(amountUsd: 5000),
          ),
        );

        expect(result.balanceUsd, 6000);
        final metadata = result.metadata as CapMetadata;
        expect(metadata.fillPercent, 100);
        expect(metadata.isOverfilled, isTrue);
      },
    );

    test('a zero-amount cap degenerates to no metadata', () {
      final result = run(
        userEnvelope(balanceUsd: 100, target: const CapView(amountUsd: 0)),
      );

      expect(result.metadata, const NoMetadata());
    });

    test('Stage with a positive balance is surfaced', () {
      final snapshot = engine(const [], const {}, [
        EnvelopeView(
          id: EnvelopeId('sys-stage'),
          name: 'Stage',
          role: EnvelopeRoleView.stage,
          balanceUsd: 1500,
          target: const NoTargetView(),
        ),
      ], today);

      final result = snapshot.envelopes.single;
      expect(result.role, EnvelopeRoleView.stage);
      expect(result.balanceUsd, 1500);
      expect(result.metadata, const NoMetadata());
    });

    test('Stage at zero balance is hidden', () {
      final snapshot = engine(const [], const {}, [
        EnvelopeView(
          id: EnvelopeId('sys-stage'),
          name: 'Stage',
          role: EnvelopeRoleView.stage,
          balanceUsd: 0,
          target: const NoTargetView(),
        ),
      ], today);

      expect(snapshot.envelopes, isEmpty);
    });

    test('Apertura (opening) with a positive balance is surfaced', () {
      final snapshot = engine(const [], const {}, [
        EnvelopeView(
          id: EnvelopeId('sys-opening'),
          name: 'Opening',
          role: EnvelopeRoleView.opening,
          balanceUsd: 900,
          target: const NoTargetView(),
        ),
      ], today);

      final result = snapshot.envelopes.single;
      expect(result.role, EnvelopeRoleView.opening);
      expect(result.balanceUsd, 900);
    });

    test('Apertura at zero balance is hidden', () {
      final snapshot = engine(const [], const {}, [
        EnvelopeView(
          id: EnvelopeId('sys-opening'),
          name: 'Opening',
          role: EnvelopeRoleView.opening,
          balanceUsd: 0,
          target: const NoTargetView(),
        ),
      ], today);

      expect(snapshot.envelopes, isEmpty);
    });

    test('Diferencial and Ajustes never appear, regardless of balance', () {
      final snapshot = engine(const [], const {}, [
        EnvelopeView(
          id: EnvelopeId('sys-differential'),
          name: 'Differential',
          role: EnvelopeRoleView.differential,
          balanceUsd: 500,
          target: const NoTargetView(),
        ),
        EnvelopeView(
          id: EnvelopeId('sys-adjustments'),
          name: 'Adjustments',
          role: EnvelopeRoleView.adjustments,
          balanceUsd: 500,
          target: const NoTargetView(),
        ),
      ], today);

      expect(snapshot.envelopes, isEmpty);
    });
  });
}
