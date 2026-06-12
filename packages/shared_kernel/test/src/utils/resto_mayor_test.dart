import 'dart:math' as math;
import 'package:test/test.dart';
import 'package:shared_kernel/src/utils/resto_mayor.dart';

void main() {
  group('repartirRestoMayor', () {
    test('reparte 100 en 3 partes iguales (mayor resto al inicio)', () {
      final weights = [1.0, 1.0, 1.0];
      final result = repartirRestoMayor(BigInt.from(100), weights);
      expect(result, equals([BigInt.from(34), BigInt.from(33), BigInt.from(33)]));
    });

    test('reparte 10 en pesos [1, 2, 3] proporcionalmente', () {
      final weights = [1.0, 2.0, 3.0];
      final result = repartirRestoMayor(BigInt.from(10), weights);
      expect(result, equals([BigInt.from(2), BigInt.from(3), BigInt.from(5)]));
    });

    test('maneja total 0', () {
      final weights = [1.0, 1.0];
      final result = repartirRestoMayor(BigInt.from(0), weights);
      expect(result, equals([BigInt.zero, BigInt.zero]));
    });

    test('maneja pesos en 0', () {
      final weights = [0.0, 0.0];
      final result = repartirRestoMayor(BigInt.from(10), weights);
      // Si todos los pesos son 0, debería dividir a partes iguales
      expect(result, equals([BigInt.from(5), BigInt.from(5)]));
    });

    test('maneja lista de pesos vacía', () {
      final result = repartirRestoMayor(BigInt.from(10), []);
      expect(result, equals([]));
    });
    
    test('maneja lista de pesos con 1 elemento', () {
      final result = repartirRestoMayor(BigInt.from(10), [0.5]);
      expect(result, equals([BigInt.from(10)]));
    });

    test('property test: la suma de las partes es siempre igual al total', () {
      final random = math.Random(42); // fixed seed for reproducibility
      for (int i = 0; i < 1000; i++) {
        final total = BigInt.from(random.nextInt(1000000));
        final n = random.nextInt(20) + 1; // 1 to 20 weights
        final weights = List.generate(n, (_) => random.nextDouble() * 100);
        
        final result = repartirRestoMayor(total, weights);
        final sum = result.fold(BigInt.zero, (sum, val) => sum + val);
        
        expect(sum, equals(total));
        expect(result.length, equals(n));
      }
    });
  });
}
