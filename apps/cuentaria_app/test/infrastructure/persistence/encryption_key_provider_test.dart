import 'package:cuentaria_app/infrastructure/persistence/encryption_key_provider.dart';
import 'package:cuentaria_app/infrastructure/persistence/secure_key_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory [SecureKeyStore] stand-in for the OS secure storage plugin,
/// which is unavailable outside a real platform (Android Keystore / iOS
/// Keychain).
class FakeSecureKeyStore implements SecureKeyStore {
  final Map<String, String> _values = {};
  int readCount = 0;

  @override
  Future<String?> read(String key) async {
    readCount++;
    return _values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}

void main() {
  group('EncryptionKeyProvider', () {
    test('first call generates a 256-bit key and persists it', () async {
      final store = FakeSecureKeyStore();
      final provider = EncryptionKeyProvider(store);

      final key = await provider.getOrCreateKey();

      expect(key.length, 32); // 256 bits
      expect(await store.read('db_encryption_key'), isNotNull);
    });

    test('a fresh provider on the same store reuses the persisted key '
        '(simulates app restart)', () async {
      final store = FakeSecureKeyStore();
      final first = await EncryptionKeyProvider(store).getOrCreateKey();
      final second = await EncryptionKeyProvider(store).getOrCreateKey();

      expect(second, first);
    });

    test('caches the key in memory after the first read', () async {
      final store = FakeSecureKeyStore();
      final provider = EncryptionKeyProvider(store);

      await provider.getOrCreateKey();
      await provider.getOrCreateKey();

      expect(store.readCount, 1);
    });

    test('two providers generate different random keys', () async {
      final keyA =
          await EncryptionKeyProvider(FakeSecureKeyStore()).getOrCreateKey();
      final keyB =
          await EncryptionKeyProvider(FakeSecureKeyStore()).getOrCreateKey();

      expect(keyA, isNot(equals(keyB)));
    });
  });
}
