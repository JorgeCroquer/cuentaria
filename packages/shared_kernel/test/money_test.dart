import 'package:test/test.dart';
import 'package:shared_kernel/shared_kernel.dart';

void main() {
  group('Money', () {
    test('equates by value (amount and currency)', () {
      final m1 = Money(amount: BigInt.from(100), currency: CurrencyCode('USD'));
      final m2 = Money(amount: BigInt.from(100), currency: CurrencyCode('USD'));
      final m3 = Money(amount: BigInt.from(100), currency: CurrencyCode('VES'));
      final m4 = Money(amount: BigInt.from(200), currency: CurrencyCode('USD'));

      expect(m1, equals(m2));
      expect(m1, isNot(equals(m3)));
      expect(m1, isNot(equals(m4)));
    });

    test('add works for the same currency', () {
      final m1 = Money(amount: BigInt.from(100), currency: CurrencyCode('USD'));
      final m2 = Money(amount: BigInt.from(250), currency: CurrencyCode('USD'));
      final result = m1.add(m2);

      expect(result.amount, equals(BigInt.from(350)));
      expect(result.currency, equals(CurrencyCode('USD')));
    });

    test('add throws ArgumentError for different currencies', () {
      final m1 = Money(amount: BigInt.from(100), currency: CurrencyCode('USD'));
      final m2 = Money(amount: BigInt.from(250), currency: CurrencyCode('VES'));

      expect(() => m1.add(m2), throwsArgumentError);
    });

    test('subtract works for the same currency', () {
      final m1 = Money(amount: BigInt.from(250), currency: CurrencyCode('USD'));
      final m2 = Money(amount: BigInt.from(100), currency: CurrencyCode('USD'));
      final result = m1.subtract(m2);

      expect(result.amount, equals(BigInt.from(150)));
      expect(result.currency, equals(CurrencyCode('USD')));
    });

    test('subtract throws ArgumentError for different currencies', () {
      final m1 = Money(amount: BigInt.from(250), currency: CurrencyCode('USD'));
      final m2 = Money(amount: BigInt.from(100), currency: CurrencyCode('VES'));

      expect(() => m1.subtract(m2), throwsArgumentError);
    });
  });
}
