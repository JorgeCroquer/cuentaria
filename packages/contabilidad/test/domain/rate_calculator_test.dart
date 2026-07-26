import 'package:decimal/decimal.dart';
import 'package:test/test.dart';

import 'package:contabilidad/domain/rate_calculator.dart';

void main() {
  group('RateCalculator', () {
    test('deriveRate returns native-per-USD from given/received cents', () {
      // $100.00 given -> 4000.00 Bs received => 40.00 Bs/USD
      final rate = RateCalculator.deriveRate(
        usdCents: BigInt.from(10000),
        nativeCents: BigInt.from(400000),
      );

      expect(rate, Decimal.parse('40'));
    });

    test('deriveNativeCents rounds once: usd * rate', () {
      // $2.50 at 20 Bs/USD => 50.00 Bs
      final nativeCents = RateCalculator.deriveNativeCents(
        usdCents: BigInt.from(250),
        rate: Decimal.parse('20'),
      );

      expect(nativeCents, BigInt.from(5000));
    });

    test('deriveNativeCents rounds a fractional result once', () {
      // $1.00 at 3.335 Bs/USD => 3.335 Bs -> rounds to 3.34 Bs (334 cents)
      final nativeCents = RateCalculator.deriveNativeCents(
        usdCents: BigInt.from(100),
        rate: Decimal.parse('3.335'),
      );

      expect(nativeCents, BigInt.from(334));
    });

    test('deriveUsdCents rounds once: native / rate', () {
      // 50.00 Bs at 20 Bs/USD => $2.50
      final usdCents = RateCalculator.deriveUsdCents(
        nativeCents: BigInt.from(5000),
        rate: Decimal.parse('20'),
      );

      expect(usdCents, BigInt.from(250));
    });

    test('toggle consistency: deriving native then re-deriving usd from it '
        'round-trips to the original given amount', () {
      final given = BigInt.from(1999);
      final rate = Decimal.parse('36.54');

      final native = RateCalculator.deriveNativeCents(
        usdCents: given,
        rate: rate,
      );
      final rederivedRate = RateCalculator.deriveRate(
        usdCents: given,
        nativeCents: native,
      );
      final rederivedNative = RateCalculator.deriveNativeCents(
        usdCents: given,
        rate: rederivedRate,
      );

      expect(rederivedNative, native);
    });

    test('deriveRate throws when given amount is zero', () {
      expect(
        () => RateCalculator.deriveRate(
          usdCents: BigInt.zero,
          nativeCents: BigInt.from(100),
        ),
        throwsArgumentError,
      );
    });

    test('deriveUsdCents throws when rate is zero', () {
      expect(
        () => RateCalculator.deriveUsdCents(
          nativeCents: BigInt.from(100),
          rate: Decimal.zero,
        ),
        throwsArgumentError,
      );
    });
  });
}
