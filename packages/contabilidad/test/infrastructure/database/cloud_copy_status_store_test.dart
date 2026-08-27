import 'dart:ffi';
import 'dart:io';

import 'package:contabilidad/infrastructure/database/cloud_copy_status_store.dart';
import 'package:contabilidad/infrastructure/database/cuentaria_database.dart';
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
  late CloudCopyStatusStore store;

  setUp(() {
    db = CuentariaDatabase(NativeDatabase.memory());
    store = CloudCopyStatusStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('returns null for both keys before anything is stored', () async {
    expect(await store.getLastSuccessAt(), isNull);
    expect(await store.getLastError(), isNull);
  });

  test('returns the stamped success date after setLastSuccessAt', () async {
    final stamp = DateTime.utc(2026, 8, 7, 14, 3);
    await store.setLastSuccessAt(stamp);

    expect(await store.getLastSuccessAt(), equals(stamp));
  });

  test('a later success stamp overwrites an earlier one', () async {
    await store.setLastSuccessAt(DateTime.utc(2026, 8, 1));
    final later = DateTime.utc(2026, 8, 7, 14, 3);
    await store.setLastSuccessAt(later);

    expect(await store.getLastSuccessAt(), equals(later));
  });

  test('returns the stored error after setLastError', () async {
    await store.setLastError('CloudUnavailable: sin internet');

    expect(
      await store.getLastError(),
      equals('CloudUnavailable: sin internet'),
    );
  });

  test('clearLastError removes the stored error', () async {
    await store.setLastError('algo falló');
    await store.clearLastError();

    expect(await store.getLastError(), isNull);
  });

  test('success and error keys are independent of each other and of '
      'other app_meta keys, e.g. device_id', () async {
    await store.setLastSuccessAt(DateTime.utc(2026, 8, 7));
    await store.setLastError('algo falló');

    final rows = await db.select(db.appMeta).get();
    expect(rows, hasLength(2));
    expect(
      rows.map((r) => r.key).toSet(),
      equals({'cloud_copy_last_success', 'cloud_copy_last_error'}),
    );
  });
}
