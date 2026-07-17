/// Schema v2 → v3 upgrade test.
///
/// Verifies [CuentariaDatabase.onUpgrade] correctly creates the [app_meta]
/// table (slice #45) when opening a v2 database, and that any pre-existing
/// rows in v2 tables survive untouched.
library;

import 'dart:io';

import 'package:contabilidad/infrastructure/database/cuentaria_database.dart';
import 'package:contabilidad/infrastructure/database/device_id_provider.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../catalog/test_helpers.dart';

void main() {
  test(
    'v2 → v3 upgrade: app_meta table created, existing data survives',
    () async {
      ensureSqlite3();

      // --- build a v2 database on disk ---
      final dir = Directory.systemTemp.createTempSync(
        'cuentaria_migration_v3_test',
      );
      final dbPath = '${dir.path}/test.db';

      try {
        // Create v2 schema via raw sqlite3 (tables from schemaVersion=2).
        final raw = sqlite3.open(dbPath);
        raw.execute('''
        PRAGMA user_version = 2;
        CREATE TABLE events (
          event_id TEXT NOT NULL,
          type TEXT NOT NULL,
          occurred_at INTEGER NOT NULL,
          recorded_at INTEGER NOT NULL,
          schema_version INTEGER NOT NULL,
          reverses TEXT,
          payload TEXT NOT NULL,
          PRIMARY KEY (event_id)
        );
        CREATE TABLE event_targets (
          event_id TEXT NOT NULL,
          dimension TEXT NOT NULL,
          target_id TEXT NOT NULL
        );
        CREATE TABLE accounts (
          id TEXT NOT NULL,
          name TEXT NOT NULL,
          native_currency TEXT NOT NULL,
          provider TEXT,
          is_archived INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          PRIMARY KEY (id)
        );
        CREATE TABLE envelopes (
          id TEXT NOT NULL,
          name TEXT NOT NULL,
          role TEXT NOT NULL,
          is_archived INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          meta TEXT,
          PRIMARY KEY (id)
        );
        CREATE TABLE cascade_config (
          row_id TEXT NOT NULL,
          steps TEXT NOT NULL,
          updated_at INTEGER NOT NULL,
          PRIMARY KEY (row_id)
        );
        -- Seed one account row so we can verify it survives the upgrade.
        INSERT INTO accounts VALUES ('acc-survive', 'My Account', 'USD', NULL, 0, 1000);
      ''');
        raw.dispose();

        // --- open with Drift (triggers onUpgrade 2 → 3) ---
        final db = CuentariaDatabase(NativeDatabase(File(dbPath)));

        // app_meta is accessible and device_id can be provisioned.
        final deviceId = await DeviceIdProvider(db).getOrCreateDeviceId();
        expect(deviceId, isNotEmpty);

        // Pre-existing account row survives.
        final accounts = await db.select(db.accounts).get();
        expect(accounts.any((r) => r.id == 'acc-survive'), isTrue);

        await db.close();
      } finally {
        dir.deleteSync(recursive: true);
      }
    },
  );
}
