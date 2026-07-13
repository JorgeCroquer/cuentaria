/// Unit tests for [KeyProvisioner] using a fake [SecureStorage].
///
/// These run in pure Dart (no device) and validate key generation + idempotence.
library;

import 'package:cuentaria_app/infrastructure/key_provisioner.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake: in-memory secure storage
// ---------------------------------------------------------------------------

class FakeSecureStorage implements SecureStorage {
  final Map<String, String> _store = {};

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String value) async => _store[key] = value;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('KeyProvisioner', () {
    test('first call generates a 256-bit (32-byte) key', () async {
      final provisioner = KeyProvisioner(FakeSecureStorage());
      final key = await provisioner.provision();

      expect(key.length, 32, reason: '256 bits = 32 bytes');
    });

    test('second call returns the same key (idempotent)', () async {
      final storage = FakeSecureStorage();
      final provisioner = KeyProvisioner(storage);

      final first = await provisioner.provision();
      final second = await provisioner.provision();

      expect(second, equals(first));
    });

    test('key is persisted in secure storage', () async {
      final storage = FakeSecureStorage();
      final provisioner = KeyProvisioner(storage);

      await provisioner.provision();

      expect(storage._store.containsKey('cuentaria.db.key'), isTrue);
    });

    test(
      'new KeyProvisioner instance reads existing key from storage',
      () async {
        final storage = FakeSecureStorage();
        final first = await KeyProvisioner(storage).provision();
        final second = await KeyProvisioner(storage).provision();

        expect(second, equals(first));
      },
    );

    test('generated key has sufficient randomness (not all-zeros)', () async {
      final provisioner = KeyProvisioner(FakeSecureStorage());
      final key = await provisioner.provision();

      // Extremely unlikely a real random key is all zeros.
      expect(key.any((b) => b != 0), isTrue);
    });

    test('two fresh provisions produce different keys', () async {
      final key1 = await KeyProvisioner(FakeSecureStorage()).provision();
      final key2 = await KeyProvisioner(FakeSecureStorage()).provision();

      // Statistically impossible to collide with Random.secure().
      expect(key1, isNot(equals(key2)));
    });
  });
}
