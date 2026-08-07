/// Stamps the local timestamp of the last successful Backup File share
/// (ADR-0021 §4/§Consequence).
///
/// Stored in the local-only [AppMeta] table (`key = 'last_backup_date'`),
/// the same key/value table [DeviceIdProvider] uses for `device_id`. Never
/// synced, never included in the Backup File itself: it identifies this
/// install, not a fact of the user's finances.
library;

import 'cuentaria_database.dart';

class LastBackupProvider {
  static const _lastBackupKey = 'last_backup_date';

  final CuentariaDatabase _db;

  LastBackupProvider(this._db);

  /// Returns the stamped date, or null if no backup has ever been made.
  Future<DateTime?> getLastBackupDate() async {
    final row =
        await (_db.select(_db.appMeta)
          ..where((t) => t.key.equals(_lastBackupKey))).getSingleOrNull();
    if (row == null) return null;
    return DateTime.parse(row.value);
  }

  /// Persists [date] as the new last-backup stamp, replacing any prior one.
  Future<void> setLastBackupDate(DateTime date) async {
    await _db
        .into(_db.appMeta)
        .insertOnConflictUpdate(
          AppMetaCompanion.insert(
            key: _lastBackupKey,
            value: date.toUtc().toIso8601String(),
          ),
        );
  }
}
