/// Stable per-install device UUID stored in [app_meta] (F2-9-d, issue #45).
///
/// On first call, generates a UUID v4 and persists it via
/// [CuentariaDatabase.setAppMeta].  Subsequent calls read it back.
/// The value is NOT synced to F3 (lives only in the local `app_meta` table).
library;

import 'package:contabilidad/infrastructure/database/cuentaria_database.dart';
import 'package:uuid/uuid.dart';

class DeviceIdProvisioner {
  static const _metaKey = 'device_id';

  final CuentariaDatabase _db;
  final Uuid _uuid;

  DeviceIdProvisioner(this._db, {Uuid uuid = const Uuid()}) : _uuid = uuid;

  /// Returns the stable per-install device_id, generating one on first call.
  Future<String> provision() async {
    final stored = await _db.getAppMeta(_metaKey);
    if (stored != null) return stored;

    final id = _uuid.v4();
    await _db.setAppMeta(_metaKey, id);
    return id;
  }
}
