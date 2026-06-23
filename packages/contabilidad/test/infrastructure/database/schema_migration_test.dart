/// Schema v1 → v2 upgrade test.
///
/// Verifies [CuentariaDatabase.onUpgrade] correctly creates the
/// [cascade_config] table when opening a v1 database, and that any
/// pre-existing rows in v1 tables survive untouched.
library;

import 'dart:io';

import 'package:contabilidad/infrastructure/cascade/drift_cascade_repository.dart';
import 'package:contabilidad/infrastructure/database/cuentaria_database.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../catalog/test_helpers.dart';

void main() {
  test(
    'v1 → v2 upgrade: cascade_config table created, existing data survives',
    () async {
      ensureSqlite3();

      // --- build a v1 database on disk ---
      final dir = Directory.systemTemp.createTempSync(
        'cuentaria_migration_test',
      );
      final dbPath = '${dir.path}/test.db';

      try {
        // Create v1 schema via raw sqlite3 (tables from schemaVersion=1).
        final raw = sqlite3.open(dbPath);
        raw.execute('''
        PRAGMA user_version = 1;
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
        -- Seed one account row so we can verify it survives the upgrade.
        INSERT INTO accounts VALUES ('acc-survive', 'My Account', 'USD', NULL, 0, 1000);
      ''');
        raw.dispose();

        // --- open with Drift (triggers onUpgrade 1 → 2) ---
        final db = CuentariaDatabase(NativeDatabase(File(dbPath)));

        // Executing any query forces Drift to apply the migration.
        final cascadeRepo = DriftCascadeRepository(db);
        await cascadeRepo.hydrate(); // touches cascade_config table

        // cascade_config is accessible (no exception above = table exists)
        expect(await cascadeRepo.load(), isNull); // no rows yet — correct

        // Pre-existing account row survives
        final accounts = await db.select(db.accounts).get();
        expect(accounts.any((r) => r.id == 'acc-survive'), isTrue);

        await db.close();
      } finally {
        dir.deleteSync(recursive: true);
      }
    },
  );
}
