import 'dart:convert';
import 'dart:math';

import 'secure_key_store.dart';

/// Provisions the random 256-bit key that encrypts the local database
/// (slice #45). Generated once on first launch and stored in OS secure
/// storage; read back and cached in memory on later launches.
///
/// Separate from the future sync DEK (ADR-0009/0014) — this key never leaves
/// the device.
class EncryptionKeyProvider {
  static const _storageKey = 'db_encryption_key';
  static const _keyLengthBytes = 32; // 256 bits

  final SecureKeyStore _store;
  List<int>? _cached;

  EncryptionKeyProvider(this._store);

  Future<List<int>> getOrCreateKey() async {
    final cached = _cached;
    if (cached != null) return cached;

    final existing = await _store.read(_storageKey);
    if (existing != null) {
      final key = base64Decode(existing);
      _cached = key;
      return key;
    }

    final generated = _generateKey();
    await _store.write(_storageKey, base64Encode(generated));
    _cached = generated;
    return generated;
  }

  List<int> _generateKey() {
    final random = Random.secure();
    return List<int>.generate(_keyLengthBytes, (_) => random.nextInt(256));
  }
}
