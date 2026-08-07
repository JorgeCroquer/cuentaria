import 'dart:ffi';
import 'dart:io';

import 'package:contabilidad/infrastructure/database/cuentaria_database.dart';
import 'package:contabilidad/infrastructure/database/last_backup_provider.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/open.dart';
import 'package:test/test.dart';

void _ensureSqlite3() {
  if (!Platform.isLinux) return;
  open.overrideForAll(() {
    try {
      return DynamicLibrary.open('libsqlite3.so');
    } catch (_) {
      // ignore: empty_catches
    }
    return DynamicLibrary.open('libsqlite3.so.0');
  });
}

void main() {
  setUpAll(_ensureSqlite3);

  late CuentariaDatabase db;
  late LastBackupProvider provider;

  setUp(() {
    db = CuentariaDatabase(NativeDatabase.memory());
    provider = LastBackupProvider(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('returns null before any backup has ever been made', () async {
    expect(await provider.getLastBackupDate(), isNull);
  });

  test('returns the stamped date after setLastBackupDate', () async {
    final stamp = DateTime.utc(2026, 8, 7, 14, 3);
    await provider.setLastBackupDate(stamp);

    expect(await provider.getLastBackupDate(), equals(stamp));
  });

  test('a later stamp overwrites an earlier one', () async {
    await provider.setLastBackupDate(DateTime.utc(2026, 8, 1));
    final later = DateTime.utc(2026, 8, 7, 14, 3);
    await provider.setLastBackupDate(later);

    expect(await provider.getLastBackupDate(), equals(later));
  });

  test('does not appear among other app_meta keys, e.g. device_id', () async {
    await provider.setLastBackupDate(DateTime.utc(2026, 8, 7));

    final rows = await db.select(db.appMeta).get();
    expect(rows, hasLength(1));
    expect(rows.single.key, equals('last_backup_date'));
  });
}
