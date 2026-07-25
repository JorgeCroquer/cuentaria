import 'package:test/test.dart';
import 'package:shared_kernel/shared_kernel.dart';

void main() {
  group('CurrencyCode', () {
    test('equates by value', () {
      final code1 = CurrencyCode('USD');
      final code2 = CurrencyCode('USD');
      final code3 = CurrencyCode('VES');

      expect(code1, equals(code2));
      expect(code1, isNot(equals(code3)));
    });

    test('throws ArgumentError if code is not 3-4 uppercase letters', () {
      expect(() => CurrencyCode('usd'), throwsArgumentError);
      expect(() => CurrencyCode('US'), throwsArgumentError);
      expect(() => CurrencyCode('USDTX'), throwsArgumentError);
      expect(() => CurrencyCode('U\$D'), throwsArgumentError);
      expect(() => CurrencyCode(''), throwsArgumentError);
    });

    for (final code in ['USD', 'VES', 'USDT']) {
      test('accepts $code', () {
        expect(() => CurrencyCode(code), returnsNormally);
      });
    }

    for (final code in ['US', 'USDTX', 'usd', 'US1']) {
      test('rejects $code', () {
        expect(() => CurrencyCode(code), throwsArgumentError);
      });
    }
  });
}
