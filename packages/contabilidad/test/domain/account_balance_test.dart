import 'package:test/test.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:contabilidad/domain/account_balance.dart';

void main() {
  group('AccountBalance baseCostOf', () {
    test('returns 0 if native.amount is 0', () {
      final balance = AccountBalance(
        native: Money(amount: BigInt.zero, currency: CurrencyCode('VES')),
        usd: 1000,
      );

      expect(balance.baseCostOf(BigInt.from(500)), equals(0));
    });

    test('returns 0 if usd is 0', () {
      final balance = AccountBalance(
        native: Money(amount: BigInt.from(1000), currency: CurrencyCode('VES')),
        usd: 0,
      );

      expect(balance.baseCostOf(BigInt.from(500)), equals(0));
    });

    test(
      'zero-native rule: returns all remaining cost when entire native is withdrawn',
      () {
        // Case with rounding to prove it returns the exact residual
        final balance = AccountBalance(
          native: Money(amount: BigInt.from(3), currency: CurrencyCode('VES')),
          usd: 10,
        );

        // Withdraw exactly 3
        expect(balance.baseCostOf(BigInt.from(3)), equals(10));
      },
    );

    test(
      'proportional withdrawal with integer arithmetic truncates correctly',
      () {
        final balance = AccountBalance(
          native: Money(
            amount: BigInt.from(10000),
            currency: CurrencyCode('VES'),
          ), // 100.00 Bs
          usd: 2500, // $25.00
        );

        // Withdraw half (50.00 Bs)
        expect(balance.baseCostOf(BigInt.from(5000)), equals(1250)); // $12.50

        // Withdraw a quarter (25.00 Bs)
        expect(balance.baseCostOf(BigInt.from(2500)), equals(625)); // $6.25
      },
    );
  });
}
