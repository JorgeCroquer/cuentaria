import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Port over OS secure storage (Android Keystore / iOS Keychain), so
/// [EncryptionKeyProvider] stays testable without a real platform.
abstract class SecureKeyStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class FlutterSecureKeyStore implements SecureKeyStore {
  final FlutterSecureStorage _storage;

  const FlutterSecureKeyStore([
    this._storage = const FlutterSecureStorage(),
  ]);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}
