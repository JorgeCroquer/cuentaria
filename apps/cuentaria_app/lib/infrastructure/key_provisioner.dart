/// Key provisioner for the at-rest SQLCipher key (F2-6, ADR-0014).
///
/// On first launch generates a random 256-bit key (32 bytes) and stores it
/// in OS secure storage (Android Keystore / iOS Keychain). Subsequent
/// launches read it back. The key never leaves the device and is separate
/// from the future sync DEK (F3).
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Port: abstraction over OS secure storage for testability.
abstract interface class SecureStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

/// Production adapter: delegates to [flutter_secure_storage].
final class FlutterSecureStorageAdapter implements SecureStorage {
  final FlutterSecureStorage _storage;

  const FlutterSecureStorageAdapter(this._storage);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

/// Provisions the per-install SQLCipher key.
///
/// Key encoding: base64-standard (44 chars for 32 raw bytes).
/// Key size: 256 bits (32 bytes) — passed directly to SQLCipher as raw bytes
/// via hex PRAGMA key, so encoding here is just for secure-storage
/// transport; callers receive the raw [Uint8List].
class KeyProvisioner {
  static const _storageKey = 'cuentaria.db.key';

  final SecureStorage _storage;
  final Random _random;

  KeyProvisioner(this._storage, {Random? random})
    : _random = random ?? Random.secure();

  /// Returns the existing key or generates and stores a new one.
  Future<Uint8List> provision() async {
    final stored = await _storage.read(_storageKey);
    if (stored != null) {
      return base64.decode(stored);
    }
    final key = _generateKey();
    await _storage.write(_storageKey, base64.encode(key));
    return key;
  }

  Uint8List _generateKey() {
    final bytes = Uint8List(32); // 256 bits
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }
}
