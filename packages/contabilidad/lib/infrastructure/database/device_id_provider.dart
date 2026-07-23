/// Provisions a stable per-install `device_id` (slice #45).
///
/// Stored once in the local-only [AppMeta] table (`key = 'device_id'`), never
/// synced. Consumed by the app to fill [TransactionMetadata.deviceId] (C1-9).
library;

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'cuentaria_database.dart';

class DeviceIdProvider {
  static const _deviceIdKey = 'device_id';

  final CuentariaDatabase _db;
  final Uuid _uuid;

  DeviceIdProvider(this._db, {Uuid uuid = const Uuid()}) : _uuid = uuid;

  /// Returns the persisted device id, generating and storing one on first
  /// call. Idempotent across calls and across app restarts (same database).
  Future<String> getOrCreateDeviceId() async {
    final existing = await _read();
    if (existing != null) return existing;

    final generated = _uuid.v4();
    await _db
        .into(_db.appMeta)
        .insert(
          AppMetaCompanion.insert(key: _deviceIdKey, value: generated),
          mode: InsertMode.insertOrIgnore,
        );

    // Re-read in case a concurrent call already won the insert race.
    return await _read() ?? generated;
  }

  Future<String?> _read() async {
    final row =
        await (_db.select(_db.appMeta)
          ..where((t) => t.key.equals(_deviceIdKey))).getSingleOrNull();
    return row?.value;
  }
}
