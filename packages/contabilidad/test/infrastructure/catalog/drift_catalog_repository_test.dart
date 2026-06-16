/// Integration tests for [DriftCatalogRepository] — seam: cache ↔ Drift.
///
/// Covers:
///   - Boot hydration: seed rows from Drift populate cache.
///   - Write persists: saveAccount/saveEnvelope visible after fresh hydrate.
///   - LWW enforced by [DriftCatalogRepository.saveAccount/saveEnvelope].
///   - deleteEnvelope removes from both DB and cache.
library;

import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'dart:ffi';
import 'dart:io';

import 'package:contabilidad/infrastructure/catalog/drift_catalog_repository.dart';
import 'package:contabilidad/infrastructure/database/cuentaria_database.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/open.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:test/test.dart';

void _ensureSqlite3() {
  if (!Platform.isLinux) return;
  open.overrideForAll(() {
    try {
      return DynamicLibrary.open('libsqlite3.so');
    } catch (_) {}
    return DynamicLibrary.open('libsqlite3.so.0');
  });
}

CuentariaDatabase _openDb() {
  _ensureSqlite3();
  return CuentariaDatabase(NativeDatabase.memory());
}

void main() {
  group('DriftCatalogRepository — boot hydration', () {
    test('system envelopes available immediately after hydrate', () async {
      final db = _openDb();
      final repo = DriftCatalogRepository(db);
      await repo.hydrate();

      expect(
        repo.getSystemEnvelope(EnvelopeRole.stage),
        EnvelopeId('sys-stage'),
      );
      expect(
        repo.getSystemEnvelope(EnvelopeRole.differential),
        EnvelopeId('sys-differential'),
      );
      expect(
        repo.getSystemEnvelope(EnvelopeRole.adjustments),
        EnvelopeId('sys-adjustments'),
      );
      expect(
        repo.getSystemEnvelope(EnvelopeRole.opening),
        EnvelopeId('sys-opening'),
      );

      await db.close();
    });

    test('re-hydrate does not duplicate system envelopes', () async {
      final db = _openDb();
      final repo = DriftCatalogRepository(db);
      await repo.hydrate();
      await repo.hydrate(); // second hydrate — no duplicate

      // All four still resolvable with same IDs
      expect(
        repo.getSystemEnvelope(EnvelopeRole.stage),
        EnvelopeId('sys-stage'),
      );

      final allEnvelopes = await db
          .select(db.envelopes)
          .get()
          .then((rows) => rows.length);
      expect(allEnvelopes, 4); // only 4, not 8

      await db.close();
    });
  });

  group('DriftCatalogRepository — write ↔ cache seam', () {
    late CuentariaDatabase db;
    late DriftCatalogRepository repo;

    setUp(() async {
      db = _openDb();
      repo = DriftCatalogRepository(db);
      await repo.hydrate();
    });

    tearDown(() => db.close());

    test('saveAccount persists to Drift and cache', () async {
      final acc = Account(
        id: AccountId('acc-persist'),
        name: 'Cash',
        nativeCurrency: CurrencyCode('USD'),
        isArchived: false,
        updatedAt: DateTime.utc(2024, 6, 1),
      );
      await repo.saveAccount(acc);

      // Sync read from cache
      expect(repo.getAccount(AccountId('acc-persist'))?.name, 'Cash');

      // Verify durable — create fresh repo on same db
      final repo2 = DriftCatalogRepository(db);
      await repo2.hydrate();
      expect(repo2.getAccount(AccountId('acc-persist'))?.name, 'Cash');
    });

    test('saveEnvelope persists to Drift and cache', () async {
      final env = Envelope(
        id: EnvelopeId('env-persist'),
        name: 'Groceries',
        role: EnvelopeRole.none,
        isArchived: false,
        updatedAt: DateTime.utc(2024, 6, 1),
      );
      await repo.saveEnvelope(env);

      expect(repo.getEnvelope(EnvelopeId('env-persist'))?.name, 'Groceries');

      final repo2 = DriftCatalogRepository(db);
      await repo2.hydrate();
      expect(repo2.getEnvelope(EnvelopeId('env-persist'))?.name, 'Groceries');
    });

    test('LWW: newer write wins in cache and DB', () async {
      final t0 = DateTime.utc(2024, 1, 1);
      final t1 = DateTime.utc(2024, 1, 2);
      final acc1 = Account(
        id: AccountId('acc-lww'),
        name: 'Old',
        nativeCurrency: CurrencyCode('USD'),
        isArchived: false,
        updatedAt: t0,
      );
      final acc2 = Account(
        id: AccountId('acc-lww'),
        name: 'New',
        nativeCurrency: CurrencyCode('USD'),
        isArchived: false,
        updatedAt: t1,
      );
      await repo.saveAccount(acc1);
      await repo.saveAccount(acc2);

      expect(repo.getAccount(AccountId('acc-lww'))?.name, 'New');

      final repo2 = DriftCatalogRepository(db);
      await repo2.hydrate();
      expect(repo2.getAccount(AccountId('acc-lww'))?.name, 'New');
    });

    test('deleteEnvelope removes from cache and DB', () async {
      final env = Envelope(
        id: EnvelopeId('env-del'),
        name: 'Temp',
        role: EnvelopeRole.none,
        isArchived: false,
        updatedAt: DateTime.utc(2024, 1, 1),
      );
      await repo.saveEnvelope(env);
      await repo.deleteEnvelope(EnvelopeId('env-del'));

      expect(repo.getEnvelope(EnvelopeId('env-del')), isNull);

      final repo2 = DriftCatalogRepository(db);
      await repo2.hydrate();
      expect(repo2.getEnvelope(EnvelopeId('env-del')), isNull);
    });

    test('system envelope rename survives reopen', () async {
      final stageId = repo.getSystemEnvelope(EnvelopeRole.stage);
      final orig = repo.getEnvelope(stageId)!;

      final renamed = Envelope(
        id: stageId,
        name: 'Stage Renamed',
        role: EnvelopeRole.stage,
        isArchived: orig.isArchived,
        updatedAt: DateTime.utc(2025, 1, 1),
      );
      await repo.saveEnvelope(renamed);
      expect(repo.getEnvelope(stageId)?.name, 'Stage Renamed');

      final repo2 = DriftCatalogRepository(db);
      await repo2.hydrate();
      expect(repo2.getEnvelope(stageId)?.name, 'Stage Renamed');
      expect(repo2.getEnvelope(stageId)?.role, EnvelopeRole.stage);
    });
  });
}
