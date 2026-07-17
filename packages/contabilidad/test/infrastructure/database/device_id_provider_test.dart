/// Tests for [DeviceIdProvider] — stable per-install UUID in `app_meta`.
library;

import 'package:contabilidad/infrastructure/database/device_id_provider.dart';
import 'package:test/test.dart';

import '../catalog/test_helpers.dart';

void main() {
  group('DeviceIdProvider', () {
    test('first call generates and persists a device id', () async {
      final db = openTestDb();
      final provider = DeviceIdProvider(db);

      final id = await provider.getOrCreateDeviceId();

      expect(id, isNotEmpty);

      final row =
          await (db.select(db.appMeta)
                ..where((t) => t.key.equals('device_id')))
              .getSingle();
      expect(row.value, id);

      await db.close();
    });

    test('subsequent calls on the same provider return the same id', () async {
      final db = openTestDb();
      final provider = DeviceIdProvider(db);

      final first = await provider.getOrCreateDeviceId();
      final second = await provider.getOrCreateDeviceId();

      expect(second, first);

      await db.close();
    });

    test(
      'a fresh provider on the same database reuses the persisted id '
      '(simulates app restart)',
      () async {
        final db = openTestDb();

        final first = await DeviceIdProvider(db).getOrCreateDeviceId();
        final second = await DeviceIdProvider(db).getOrCreateDeviceId();

        expect(second, first);

        await db.close();
      },
    );
  });
}
