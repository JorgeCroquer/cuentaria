/// Unit tests for [DeviceIdProvisioner].
///
/// Uses [NativeDatabase.memory()] from Drift — pure Dart, no device required.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:cuentaria_app/infrastructure/device_id_provisioner.dart';
import 'package:contabilidad/infrastructure/database/cuentaria_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';

// WSL/Debian ship libsqlite3.so.0 without the unversioned dev symlink; fall
// back so flutter test can load sqlite3 in CI and on developer machines.
void _configureSqlite() {
  if (!Platform.isLinux) return;
  open.overrideForAll(() {
    try {
      return DynamicLibrary.open('libsqlite3.so');
    } catch (_) {}
    return DynamicLibrary.open('libsqlite3.so.0');
  });
}

CuentariaDatabase _openInMemory() => CuentariaDatabase(NativeDatabase.memory());

void main() {
  setUpAll(_configureSqlite);

  group('DeviceIdProvisioner', () {
    late CuentariaDatabase db;
    late DeviceIdProvisioner provisioner;

    setUp(() {
      db = _openInMemory();
      provisioner = DeviceIdProvisioner(db);
    });

    tearDown(() => db.close());

    test('first call generates a non-empty UUID', () async {
      final id = await provisioner.provision();

      expect(id, isNotEmpty);
      // UUID v4 format: 8-4-4-4-12 hex chars.
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(id),
        isTrue,
        reason: 'should be UUID v4',
      );
    });

    test('second call returns same device_id (idempotent)', () async {
      final first = await provisioner.provision();
      final second = await provisioner.provision();

      expect(second, equals(first));
    });

    test('device_id persisted in app_meta table', () async {
      final id = await provisioner.provision();

      final stored = await db.getAppMeta('device_id');
      expect(stored, equals(id));
    });

    test(
      'new provisioner instance on same DB reads existing device_id',
      () async {
        final id1 = await DeviceIdProvisioner(db).provision();
        final id2 = await DeviceIdProvisioner(db).provision();

        expect(id2, equals(id1));
      },
    );

    test('two fresh DBs produce different device_ids', () async {
      final db2 = _openInMemory();
      addTearDown(db2.close);

      final id1 = await DeviceIdProvisioner(db).provision();
      final id2 = await DeviceIdProvisioner(db2).provision();

      expect(id1, isNot(equals(id2)));
    });
  });

  group('CuentariaDatabase.getAppMeta / setAppMeta', () {
    late CuentariaDatabase db;

    setUp(() => db = _openInMemory());
    tearDown(() => db.close());

    test('getAppMeta returns null for unknown key', () async {
      expect(await db.getAppMeta('nonexistent'), isNull);
    });

    test('setAppMeta then getAppMeta round-trips', () async {
      await db.setAppMeta('foo', 'bar');
      expect(await db.getAppMeta('foo'), 'bar');
    });

    test('setAppMeta upserts (no duplicate key)', () async {
      await db.setAppMeta('k', 'v1');
      await db.setAppMeta('k', 'v2');
      expect(await db.getAppMeta('k'), 'v2');
    });
  });
}
