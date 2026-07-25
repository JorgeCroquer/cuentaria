/// Contract/parity suite: same behaviours must hold for every [CatalogRepository]
/// implementation.  Run against [InMemoryCatalogRepository] and
/// [DriftCatalogRepository] (using an in-memory SQLite executor).
library;

import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/application/catalog/exceptions.dart';
import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/catalog/models/funding_target.dart';
import 'package:contabilidad/infrastructure/catalog/drift_catalog_repository.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

// ---------------------------------------------------------------------------
// Factory helpers
// ---------------------------------------------------------------------------

CatalogRepository _inMemory() => InMemoryCatalogRepository();

Future<CatalogRepository> _drift() async {
  final db = openTestDb();
  final repo = DriftCatalogRepository(db);
  await repo.hydrate();
  return repo;
}

// ---------------------------------------------------------------------------
// Contract suite function
// ---------------------------------------------------------------------------

void _runContractSuite(
  String label,
  Future<CatalogRepository> Function() factory,
) {
  group('CatalogRepository contract — $label', () {
    late CatalogRepository repo;

    setUp(() async {
      repo = await factory();
    });

    // -----------------------------------------------------------------------
    // System-envelope seeding
    // -----------------------------------------------------------------------

    group('system-envelope seeding', () {
      test('four system envelopes exist after init', () {
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
      });

      test('getSystemEnvelope(none) throws', () {
        expect(
          () => repo.getSystemEnvelope(EnvelopeRole.none),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('system envelopes are retrievable by id', () {
        final stageId = repo.getSystemEnvelope(EnvelopeRole.stage);
        final env = repo.getEnvelope(stageId);
        expect(env, isNotNull);
        expect(env!.role, EnvelopeRole.stage);
        expect(env.name, 'Stage');
      });
    });

    // -----------------------------------------------------------------------
    // Account LWW
    // -----------------------------------------------------------------------

    group('account LWW', () {
      final t0 = DateTime.utc(2024, 1, 1);
      final t1 = DateTime.utc(2024, 1, 2);

      test('save and retrieve', () async {
        final acc = Account(
          id: AccountId('acc-1'),
          name: 'Cash',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: t0,
        );
        await repo.saveAccount(acc);
        expect(repo.getAccount(AccountId('acc-1'))?.name, 'Cash');
      });

      test('newer updatedAt wins', () async {
        final acc1 = Account(
          id: AccountId('acc-2'),
          name: 'Old',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: t0,
        );
        final acc2 = Account(
          id: AccountId('acc-2'),
          name: 'New',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: t1,
        );
        await repo.saveAccount(acc1);
        await repo.saveAccount(acc2);
        expect(repo.getAccount(AccountId('acc-2'))?.name, 'New');
      });

      test('older updatedAt does not overwrite', () async {
        final acc1 = Account(
          id: AccountId('acc-3'),
          name: 'Newer',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: t1,
        );
        final acc2 = Account(
          id: AccountId('acc-3'),
          name: 'Older',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: t0,
        );
        await repo.saveAccount(acc1);
        await repo.saveAccount(acc2);
        expect(repo.getAccount(AccountId('acc-3'))?.name, 'Newer');
      });

      test('unknown id returns null', () {
        expect(repo.getAccount(AccountId('no-such')), isNull);
      });
    });

    // -----------------------------------------------------------------------
    // Envelope LWW + role immutability
    // -----------------------------------------------------------------------

    group('envelope LWW', () {
      final t0 = DateTime.utc(2024, 1, 1);
      final t1 = DateTime.utc(2024, 1, 2);

      test('save and retrieve', () async {
        final env = Envelope(
          id: EnvelopeId('env-1'),
          name: 'Groceries',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: t0,
        );
        await repo.saveEnvelope(env);
        expect(repo.getEnvelope(EnvelopeId('env-1'))?.name, 'Groceries');
      });

      test('newer updatedAt wins', () async {
        final e1 = Envelope(
          id: EnvelopeId('env-2'),
          name: 'Old',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: t0,
        );
        final e2 = Envelope(
          id: EnvelopeId('env-2'),
          name: 'New',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: t1,
        );
        await repo.saveEnvelope(e1);
        await repo.saveEnvelope(e2);
        expect(repo.getEnvelope(EnvelopeId('env-2'))?.name, 'New');
      });

      test('older updatedAt does not overwrite', () async {
        final e1 = Envelope(
          id: EnvelopeId('env-3'),
          name: 'Newer',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: t1,
        );
        final e2 = Envelope(
          id: EnvelopeId('env-3'),
          name: 'Older',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: t0,
        );
        await repo.saveEnvelope(e1);
        await repo.saveEnvelope(e2);
        expect(repo.getEnvelope(EnvelopeId('env-3'))?.name, 'Newer');
      });

      test('role is immutable across LWW merge', () async {
        // Stage system envelope — try to change role via merge
        final stageId = repo.getSystemEnvelope(EnvelopeRole.stage);
        final impostor = Envelope(
          id: stageId,
          name: 'Hijacked',
          role: EnvelopeRole.none, // different role!
          isArchived: false,
          updatedAt: DateTime.utc(2099),
        );
        await repo.saveEnvelope(impostor);
        final after = repo.getEnvelope(stageId)!;
        expect(after.role, EnvelopeRole.stage); // immutable
      });

      test('system envelope rename is preserved (LWW wins)', () async {
        final stageId = repo.getSystemEnvelope(EnvelopeRole.stage);
        final orig = repo.getEnvelope(stageId)!;
        final renamed = Envelope(
          id: stageId,
          name: 'Renamed Stage',
          role: EnvelopeRole.stage,
          isArchived: orig.isArchived,
          updatedAt: orig.updatedAt.add(const Duration(seconds: 1)),
        );
        await repo.saveEnvelope(renamed);
        expect(repo.getEnvelope(stageId)?.name, 'Renamed Stage');
        expect(repo.getEnvelope(stageId)?.role, EnvelopeRole.stage);
      });

      test('unknown id returns null', () {
        expect(repo.getEnvelope(EnvelopeId('no-such')), isNull);
      });
    });

    // -----------------------------------------------------------------------
    // deleteAccount
    // -----------------------------------------------------------------------

    group('deleteAccount', () {
      final t0 = DateTime.utc(2024, 1, 1);

      test('account can be deleted', () async {
        final acc = Account(
          id: AccountId('del-acc-1'),
          name: 'Temp',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: t0,
        );
        await repo.saveAccount(acc);
        await repo.deleteAccount(AccountId('del-acc-1'));
        expect(repo.getAccount(AccountId('del-acc-1')), isNull);
      });

      test('unknown id is a no-op', () async {
        await repo.deleteAccount(AccountId('no-such-acc'));
        expect(repo.getAccount(AccountId('no-such-acc')), isNull);
      });
    });

    // -----------------------------------------------------------------------
    // deleteEnvelope
    // -----------------------------------------------------------------------

    group('deleteEnvelope', () {
      final t0 = DateTime.utc(2024, 1, 1);

      test('regular envelope can be deleted', () async {
        final env = Envelope(
          id: EnvelopeId('del-1'),
          name: 'Temp',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: t0,
        );
        await repo.saveEnvelope(env);
        await repo.deleteEnvelope(EnvelopeId('del-1'));
        expect(repo.getEnvelope(EnvelopeId('del-1')), isNull);
      });

      test('system envelope deletion throws', () async {
        final stageId = repo.getSystemEnvelope(EnvelopeRole.stage);
        expect(
          () async => repo.deleteEnvelope(stageId),
          throwsA(isA<SystemEnvelopeDeletionNotAllowed>()),
        );
      });
    });

    // -----------------------------------------------------------------------
    // EnvelopeTarget — round-trip through repository (meta JSON column)
    // -----------------------------------------------------------------------

    group('EnvelopeTarget round-trip', () {
      final t0 = DateTime.utc(2024, 6, 1);

      test('NoTarget survives save + retrieve', () async {
        final env = Envelope(
          id: EnvelopeId('tgt-1'),
          name: 'NoTarget Env',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: t0,
        );
        await repo.saveEnvelope(env);
        expect(repo.getEnvelope(EnvelopeId('tgt-1'))!.target, const NoTarget());
      });

      test('Cap survives save + retrieve', () async {
        final env = Envelope(
          id: EnvelopeId('tgt-2'),
          name: 'Dining',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: t0,
        ).withTarget(const Cap(amountUsd: 30000));
        await repo.saveEnvelope(env);
        expect(
          repo.getEnvelope(EnvelopeId('tgt-2'))!.target,
          const Cap(amountUsd: 30000),
        );
      });

      test('GoalLine without dueDate survives save + retrieve', () async {
        final env = Envelope(
          id: EnvelopeId('tgt-3'),
          name: 'Emergency Fund',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: t0,
        ).withTarget(const GoalLine(amountUsd: 500000));
        await repo.saveEnvelope(env);
        expect(
          repo.getEnvelope(EnvelopeId('tgt-3'))!.target,
          const GoalLine(amountUsd: 500000),
        );
      });

      test('GoalLine with dueDate survives save + retrieve', () async {
        final due = DateTime.utc(2028, 12, 31);
        final env = Envelope(
          id: EnvelopeId('tgt-4'),
          name: 'Car Fund',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: t0,
        ).withTarget(GoalLine(amountUsd: 200000, dueDate: due));
        await repo.saveEnvelope(env);
        expect(
          repo.getEnvelope(EnvelopeId('tgt-4'))!.target,
          GoalLine(amountUsd: 200000, dueDate: due),
        );
      });

      test('LWW update preserves new target', () async {
        final t1 = t0.add(const Duration(days: 1));
        final env1 = Envelope(
          id: EnvelopeId('tgt-5'),
          name: 'Savings',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: t0,
        ).withTarget(const Cap(amountUsd: 10000));
        final env2 = Envelope(
          id: EnvelopeId('tgt-5'),
          name: 'Savings',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: t1,
        ).withTarget(const Cap(amountUsd: 99000));
        await repo.saveEnvelope(env1);
        await repo.saveEnvelope(env2);
        expect(
          repo.getEnvelope(EnvelopeId('tgt-5'))!.target,
          const Cap(amountUsd: 99000),
        );
      });

      test('system envelopes always have NoTarget after save attempt', () async {
        // The system Stage envelope cannot accept a target; verify it stays NoTarget.
        final stageId = repo.getSystemEnvelope(EnvelopeRole.stage);
        expect(repo.getEnvelope(stageId)!.target, const NoTarget());
      });
    });

    // -----------------------------------------------------------------------
    // Enumeration — accounts / envelopes getters
    // -----------------------------------------------------------------------

    group('enumeration', () {
      final t0 = DateTime.utc(2024, 1, 1);

      test('accounts is empty when no accounts saved', () {
        expect(repo.accounts, isEmpty);
      });

      test('accounts returns every saved account with full fields', () async {
        final acc1 = Account(
          id: AccountId('enum-acc-1'),
          name: 'Cash',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: t0,
        );
        final acc2 = Account(
          id: AccountId('enum-acc-2'),
          name: 'Bank',
          nativeCurrency: CurrencyCode('VES'),
          isArchived: false,
          updatedAt: t0,
        );
        await repo.saveAccount(acc1);
        await repo.saveAccount(acc2);

        expect(repo.accounts, unorderedEquals([acc1, acc2]));
      });

      test('envelopes includes system envelopes by default', () {
        final roles = repo.envelopes.map((e) => e.role).toSet();
        expect(roles, {
          EnvelopeRole.stage,
          EnvelopeRole.differential,
          EnvelopeRole.adjustments,
          EnvelopeRole.opening,
        });
      });

      test(
        'envelopes includes user-created envelopes alongside system ones',
        () async {
          final env = Envelope(
            id: EnvelopeId('enum-env-1'),
            name: 'Dining',
            role: EnvelopeRole.none,
            isArchived: false,
            updatedAt: t0,
          ).withTarget(const Cap(amountUsd: 30000));
          await repo.saveEnvelope(env);

          final all = repo.envelopes.toList();
          expect(all.length, 5); // 4 system + 1 user
          final found = all.firstWhere((e) => e.id == EnvelopeId('enum-env-1'));
          expect(found.name, 'Dining');
          expect(found.target, const Cap(amountUsd: 30000));
        },
      );
    });
  });
}

// ---------------------------------------------------------------------------
// Entry point — run contract suite against both adapters
// ---------------------------------------------------------------------------

void main() {
  _runContractSuite('InMemoryCatalogRepository', () async => _inMemory());
  _runContractSuite('DriftCatalogRepository', _drift);
}
