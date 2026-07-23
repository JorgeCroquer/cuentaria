import 'package:cuentaria_app/infrastructure/persistence/encrypted_db_executor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('keyToSqlCipherPragma', () {
    test('encodes a key as a SQLCipher raw-key hex literal', () {
      final pragma = keyToSqlCipherPragma([0x00, 0x0f, 0xff]);

      expect(pragma, "x'000fff'");
    });

    test('encodes a 256-bit key as a 64-hex-char literal', () {
      final key = List<int>.generate(32, (i) => i);

      final pragma = keyToSqlCipherPragma(key);

      // "x'" + 64 hex chars + "'"
      expect(pragma.length, 2 + 64 + 1);
      expect(pragma, startsWith("x'"));
      expect(pragma, endsWith("'"));
    });
  });
}
