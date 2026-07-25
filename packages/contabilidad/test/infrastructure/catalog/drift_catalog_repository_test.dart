/// Integration tests for [DriftCatalogRepository] — seam: cache ↔ Drift.
///
/// These tests exercise the cache hydration seam: writes go to Drift,
/// a second [DriftCatalogRepository] instance on the **same open
/// [NativeDatabase.memory()]** re-hydrates from Drift rows, verifying
/// that the durable path (cache → Drift → fresh hydration) is end-to-end
/// correct.  True close/reopen durability across process boundaries is an
/// e2e concern (F2 user-story 27).
library;

import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/infrastructure/catalog/drift_catalog_repository.dart';
import 'package:contabilidad/infrastructure/database/cuentaria_database.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('DriftCatalogRepository — boot hydration', () {
    test('system envelopes available immediately after hydrate', () async {
      final db = openTestDb();
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
      final db = openTestDb();
      final repo = DriftCatalogRepository(db);
      await repo.hydrate();
      await repo.hydrate(); // second hydrate — idempotent

      // All four still resolvable with same IDs
      expect(
        repo.getSystemEnvelope(EnvelopeRole.stage),
        EnvelopeId('sys-stage'),
      );

      final rowCount = await db
          .select(db.envelopes)
          .get()
          .then((rows) => rows.length);
      expect(rowCount, 4); // only 4, not 8

      await db.close();
    });
  });

  group('DriftCatalogRepository — write ↔ cache seam', () {
    late CuentariaDatabase db;
    late DriftCatalogRepository repo;

    setUp(() async {
      db = openTestDb();
      repo = DriftCatalogRepository(db);
      await repo.hydrate();
    });

    tearDown(() => db.close());

    /// Verifies that data written through [repo] is visible to a fresh
    /// [DriftCatalogRepository] instance that re-hydrates from the same
    /// in-memory database (same-process cache invalidation path).
    test('saveAccount persists to Drift; fresh hydration sees it', () async {
      final acc = Account(
        id: AccountId('acc-persist'),
        name: 'Cash',
        nativeCurrency: CurrencyCode('USD'),
        isArchived: false,
        updatedAt: DateTime.utc(2024, 6, 1),
      );
      await repo.saveAccount(acc);

      // Sync read from existing cache
      expect(repo.getAccount(AccountId('acc-persist'))?.name, 'Cash');

      // Fresh repo on same DB re-hydrates and sees the row
      final repo2 = DriftCatalogRepository(db);
      await repo2.hydrate();
      expect(repo2.getAccount(AccountId('acc-persist'))?.name, 'Cash');
    });

    test('saveEnvelope persists to Drift; fresh hydration sees it', () async {
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

    test('LWW: newer write wins in cache and Drift', () async {
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

    test('deleteEnvelope removes from cache and Drift', () async {
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

    test('saveAccount persists meta JSON; fresh hydration sees it', () async {
      final acc = Account(
        id: AccountId('acc-color'),
        name: 'Bancamiga',
        nativeCurrency: CurrencyCode('USD'),
        isArchived: false,
        updatedAt: DateTime.utc(2024, 6, 1),
        meta: {'color': '#FF5500'},
      );
      await repo.saveAccount(acc);

      expect(repo.getAccount(AccountId('acc-color'))?.colorHex, '#FF5500');

      final repo2 = DriftCatalogRepository(db);
      await repo2.hydrate();
      expect(repo2.getAccount(AccountId('acc-color'))?.colorHex, '#FF5500');
    });

    test('system envelope rename visible after fresh hydration', () async {
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
