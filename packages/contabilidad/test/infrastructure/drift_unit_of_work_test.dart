/// [DriftUnitOfWork] is what makes restoring a Backup File all-or-nothing
/// (ADR-0021 §6) when the failure happens **while writing**, not while
/// parsing. That path cannot be exercised with the in-memory adapters — they
/// have no transaction to roll back — so this suite runs against real Drift
/// on in-memory SQLite.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/infrastructure/catalog/drift_catalog_repository.dart';
import 'package:contabilidad/infrastructure/database/cuentaria_database.dart';
import 'package:contabilidad/infrastructure/database/drift_unit_of_work.dart';
import 'package:drift/native.dart';
import 'package:shared_kernel/shared_kernel.dart';
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

Account _account(String id, String name) => Account(
  id: AccountId(id),
  name: name,
  nativeCurrency: CurrencyCode('USD'),
  isArchived: false,
  updatedAt: DateTime.utc(2026, 8, 1),
);

void main() {
  setUpAll(_ensureSqlite3);

  late CuentariaDatabase db;
  late DriftCatalogRepository catalog;
  late DriftUnitOfWork unitOfWork;

  setUp(() async {
    db = CuentariaDatabase(NativeDatabase.memory());
    catalog = DriftCatalogRepository(db);
    await catalog.hydrate();
    unitOfWork = DriftUnitOfWork(db, onRollback: [catalog.hydrate]);
  });

  tearDown(() async => db.close());

  test('commits every write when the body completes', () async {
    await unitOfWork.run(() async {
      await catalog.saveAccount(_account('acc-1', 'Efectivo'));
      await catalog.saveAccount(_account('acc-2', 'Banco'));
    });

    expect(await db.select(db.accounts).get(), hasLength(2));
    expect(catalog.getAccount(AccountId('acc-2'))?.name, equals('Banco'));
  });

  test('a failure halfway through leaves no row written', () async {
    await expectLater(
      unitOfWork.run(() async {
        await catalog.saveAccount(_account('acc-1', 'Efectivo'));
        await catalog.saveAccount(_account('acc-2', 'Banco'));
        throw StateError('disk full');
      }),
      throwsA(isA<StateError>()),
    );

    // Not "only the second one is missing" — none of them landed.
    expect(await db.select(db.accounts).get(), isEmpty);
  });

  test(
    'a failure halfway through does not keep a phantom in the cache',
    () async {
      await expectLater(
        unitOfWork.run(() async {
          await catalog.saveAccount(_account('acc-1', 'Efectivo'));
          throw StateError('disk full');
        }),
        throwsA(isA<StateError>()),
      );

      // The repository caches writes in memory, so without the reload it would
      // keep serving an account that never reached disk.
      expect(catalog.getAccount(AccountId('acc-1')), isNull);
      expect(catalog.accounts, isEmpty);
    },
  );

  test('a rollback leaves rows that were already committed alone', () async {
    await unitOfWork.run(() async {
      await catalog.saveAccount(_account('acc-1', 'Efectivo'));
    });

    await expectLater(
      unitOfWork.run(() async {
        await catalog.saveAccount(_account('acc-2', 'Banco'));
        throw StateError('disk full');
      }),
      throwsA(isA<StateError>()),
    );

    expect(await db.select(db.accounts).get(), hasLength(1));
    expect(catalog.getAccount(AccountId('acc-1'))?.name, equals('Efectivo'));
    expect(catalog.getAccount(AccountId('acc-2')), isNull);
  });
}
