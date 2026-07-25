/// Schema v3 → v4 upgrade test.
///
/// Verifies [CuentariaDatabase.onUpgrade] correctly adds the nullable
/// `meta` column to the `accounts` table (#94 — color tag, FundingTarget
/// pattern) when opening a v3 database, and that any pre-existing rows in
/// v3 tables survive untouched.
library;

import 'dart:io';

import 'package:contabilidad/infrastructure/database/cuentaria_database.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../catalog/test_helpers.dart';

void main() {
  test(
    'v3 → v4 upgrade: accounts.meta column added, existing data survives',
    () async {
      ensureSqlite3();

      final dir = Directory.systemTemp.createTempSync(
        'cuentaria_migration_v4_test',
      );
      final dbPath = '${dir.path}/test.db';

      try {
        // Create v3 schema via raw sqlite3 (tables from schemaVersion=3).
        final raw = sqlite3.open(dbPath);
        raw.execute('''
        PRAGMA user_version = 3;
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
        CREATE TABLE app_meta (
          key TEXT NOT NULL,
          value TEXT NOT NULL,
          PRIMARY KEY (key)
        );
        -- Seed one account row so we can verify it survives the upgrade.
        INSERT INTO accounts VALUES ('acc-survive', 'My Account', 'USD', NULL, 0, 1000);
      ''');
        raw.dispose();

        // --- open with Drift (triggers onUpgrade 3 → 4) ---
        final db = CuentariaDatabase(NativeDatabase(File(dbPath)));

        final accounts = await db.select(db.accounts).get();
        final survivor = accounts.singleWhere((r) => r.id == 'acc-survive');
        expect(survivor.name, 'My Account');
        expect(survivor.meta, isNull);

        // The new column accepts writes going forward.
        await (db.update(db.accounts)..where(
          (t) => t.id.equals('acc-survive'),
        )).write(const AccountsCompanion(meta: Value('{"color":"#FF5500"}')));
        final updated =
            await (db.select(db.accounts)
              ..where((t) => t.id.equals('acc-survive'))).getSingle();
        expect(updated.meta, '{"color":"#FF5500"}');

        await db.close();
      } finally {
        dir.deleteSync(recursive: true);
      }
    },
  );
}
