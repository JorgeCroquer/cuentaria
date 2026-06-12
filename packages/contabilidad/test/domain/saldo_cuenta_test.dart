import 'package:test/test.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:contabilidad/domain/saldo_cuenta.dart';

void main() {
  group('SaldoCuenta costoBaseDe', () {
    test('devuelve 0 si native.amount es 0', () {
      final saldo = SaldoCuenta(
        native: Money(amount: BigInt.zero, currency: CurrencyCode('VES')),
        usd: 1000,
      );
      
      expect(saldo.costoBaseDe(BigInt.from(500)), equals(0));
    });

    test('devuelve 0 si usd es 0', () {
      final saldo = SaldoCuenta(
        native: Money(amount: BigInt.from(1000), currency: CurrencyCode('VES')),
        usd: 0,
      );
      
      expect(saldo.costoBaseDe(BigInt.from(500)), equals(0));
    });

    test('regla cero-native: devuelve todo el costo restante si se extrae todo el native', () {
      // Un caso con redondeo para probar que devuelve el residuo exacto
      final saldo = SaldoCuenta(
        native: Money(amount: BigInt.from(3), currency: CurrencyCode('VES')),
        usd: 10,
      );
      
      // Extraemos exactamente 3
      expect(saldo.costoBaseDe(BigInt.from(3)), equals(10));
    });

    test('extracción proporcional con aritmética entera trunca correctamente', () {
      final saldo = SaldoCuenta(
        native: Money(amount: BigInt.from(10000), currency: CurrencyCode('VES')), // 100.00 Bs
        usd: 2500, // $25.00
      );
      
      // Extraemos la mitad (50.00 Bs)
      expect(saldo.costoBaseDe(BigInt.from(5000)), equals(1250)); // $12.50
      
      // Extraemos un cuarto (25.00 Bs)
      expect(saldo.costoBaseDe(BigInt.from(2500)), equals(625)); // $6.25
    });
  });
}
