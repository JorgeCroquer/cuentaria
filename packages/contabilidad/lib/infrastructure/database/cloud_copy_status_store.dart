/// Persists [CloudCopyUseCase]'s status (issue #222, ADR-0023 §4/§8): when
/// the Cloud Copy last succeeded and, independently, its last error.
///
/// Stored in the local-only [AppMeta] table, the same key/value table
/// [DeviceIdProvider] and [LastBackupProvider] use — two new keys, no Drift
/// migration. Never synced: it describes this install's Cloud Copy attempts,
/// not a fact of the user's finances.
library;

import 'cuentaria_database.dart';

class CloudCopyStatusStore {
  static const _lastSuccessKey = 'cloud_copy_last_success';
  static const _lastErrorKey = 'cloud_copy_last_error';

  final CuentariaDatabase _db;

  CloudCopyStatusStore(this._db);

  /// The timestamp of the last successful push or pull, or null if the
  /// Cloud Copy has never succeeded.
  Future<DateTime?> getLastSuccessAt() async {
    final row = await _read(_lastSuccessKey);
    if (row == null) return null;
    return DateTime.parse(row);
  }

  /// Persists [at] as the new last-success stamp, replacing any prior one.
  Future<void> setLastSuccessAt(DateTime at) async {
    await _write(_lastSuccessKey, at.toUtc().toIso8601String());
  }

  /// The last error message, or null if none is stored.
  Future<String?> getLastError() => _read(_lastErrorKey);

  /// Persists [message] as the new last-error, replacing any prior one.
  Future<void> setLastError(String message) => _write(_lastErrorKey, message);

  /// Removes the stored error, e.g. after a subsequent success.
  Future<void> clearLastError() async {
    await (_db.delete(_db.appMeta)
      ..where((t) => t.key.equals(_lastErrorKey))).go();
  }

  Future<String?> _read(String key) async {
    final row =
        await (_db.select(_db.appMeta)
          ..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> _write(String key, String value) async {
    await _db
        .into(_db.appMeta)
        .insertOnConflictUpdate(
          AppMetaCompanion.insert(key: key, value: value),
        );
  }
}
