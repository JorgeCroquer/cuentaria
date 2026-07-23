import 'package:decimal/decimal.dart';
import 'package:patrimonio/domain/account_view.dart';
import 'package:patrimonio/domain/patrimonio_engine.dart';
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
    test(
      'canonical case: cost \$100 at executed 75, parallel 100 -> today '
      '\$75 / P&L -\$25, BCV 50 -> reference \$150',
      () {
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

        final snapshot = engine([account], rates);

        expect(snapshot.realCostUsdCents, 10000);
        expect(snapshot.todayValueUsdCents, 7500);
        expect(snapshot.unrealizedPnlUsdCents, -2500);
        expect(snapshot.bcvReferenceUsdCents, 15000);
        expect(snapshot.hasMissingRate, isFalse);

        final group = snapshot.accountGroups.single;
        expect(group.currency, ves);
        expect(group.hasRate, isTrue);
        expect(group.observedAt, observedAt);
      },
    );

    test(
      'missing rate: currency without an observation falls back to real '
      'cost and is flagged, never a silent 1:1',
      () {
        final account = vesAccount(
          native: BigInt.from(750000),
          realCostUsdCents: 10000,
        );

        final snapshot = engine([account], const {});

        expect(snapshot.realCostUsdCents, 10000);
        expect(snapshot.todayValueUsdCents, 10000);
        expect(snapshot.bcvReferenceUsdCents, 10000);
        expect(snapshot.unrealizedPnlUsdCents, 0);
        expect(snapshot.hasMissingRate, isTrue);
        expect(snapshot.accountGroups.single.hasRate, isFalse);
      },
    );

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

      final snapshot = engine([account], rates);

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

      final snapshot = engine([live, archived], rates);

      expect(snapshot.realCostUsdCents, 10000);
      expect(snapshot.accountGroups.single.realCostUsdCents, 10000);
    });

    test('empty catalog produces a zeroed snapshot with no groups', () {
      final snapshot = engine(const [], const {});

      expect(snapshot.realCostUsdCents, 0);
      expect(snapshot.todayValueUsdCents, 0);
      expect(snapshot.unrealizedPnlUsdCents, 0);
      expect(snapshot.bcvReferenceUsdCents, 0);
      expect(snapshot.hasMissingRate, isFalse);
      expect(snapshot.accountGroups, isEmpty);
    });

    test(
      'USD accounts bypass rates entirely, valuing at par with no '
      'observation needed',
      () {
        final account = AccountView(
          id: AccountId('acc-usd'),
          currency: usd,
          nativeMinorAmount: BigInt.from(2500),
          realCostUsdCents: 2500,
          isArchived: false,
        );

        final snapshot = engine([account], const {});

        expect(snapshot.realCostUsdCents, 2500);
        expect(snapshot.todayValueUsdCents, 2500);
        expect(snapshot.bcvReferenceUsdCents, 2500);
        expect(snapshot.hasMissingRate, isFalse);
        expect(snapshot.accountGroups.single.hasRate, isTrue);
      },
    );

    test('single rounding per account: native/rate rounds once, half away '
        'from zero', () {
      final account = vesAccount(native: BigInt.from(100001), realCostUsdCents: 1);
      final rates = {
        ves: RateView(
          currency: ves,
          parallel: RateObservationView(
            nativePerUsd: Decimal.parse('3'),
            observedAt: observedAt,
          ),
        ),
      };

      final snapshot = engine([account], rates);

      // 100001 / 3 = 33333.67 -> rounds to 33334.
      expect(snapshot.todayValueUsdCents, 33334);
    });
  });
}
