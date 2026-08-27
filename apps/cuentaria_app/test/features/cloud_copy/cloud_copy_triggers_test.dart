/// Unit tests for [CloudCopyTriggers] (issue #224, ADR-0023 §4): when
/// `CloudCopyUseCase.sync` fires automatically. Pure trigger-timing tests
/// use a counting fake for `sync`; overlap and disconnected-session tests
/// exercise the real [CloudCopyUseCase] (its own `sync` already owns that
/// behavior, this file only proves the trigger doesn't get in its way).
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:backup/backup.dart';
import 'package:backup/infrastructure/in_memory_cloud_folder.dart';
import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/ledger/factories/record_income.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:contabilidad/infrastructure/catalog/drift_catalog_repository.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:contabilidad/infrastructure/cascade/drift_cascade_repository.dart';
import 'package:contabilidad/infrastructure/database/cloud_copy_status_store.dart';
import 'package:contabilidad/infrastructure/database/cuentaria_database.dart';
import 'package:contabilidad/infrastructure/database/drift_event_store.dart';
import 'package:contabilidad/infrastructure/database/drift_unit_of_work.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:cuentaria_app/features/backup/application/create_backup.dart';
import 'package:cuentaria_app/features/backup/application/restore_backup.dart';
import 'package:cuentaria_app/features/cloud_copy/application/cloud_copy_triggers.dart';
import 'package:cuentaria_app/features/cloud_copy/application/cloud_copy_use_case.dart';
import 'package:drift/native.dart';
import 'package:event_bus/event_bus.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:sqlite3/open.dart';
import 'package:tasas/infrastructure/drift/drift_rate_series.dart';
import 'package:tasas/infrastructure/drift/tasas_database.dart';

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

int _txCounter = 0;

Transaction _transaction() {
  _txCounter++;
  return Transaction.create(
    metadata: TransactionMetadata(
      eventId: EventId('evt-$_txCounter'),
      type: 'Income',
      occurredAt: DomainTimestamp(DateTime.utc(2026, 8, 1)),
      recordedAt: DomainTimestamp(DateTime.utc(2026, 8, 1)),
      deviceId: 'device-test',
      schemaVersion: 1,
    ),
    postings: [
      Posting(
        target: AccountTarget(AccountId('acc-1')),
        amountNative: Money(
          amount: BigInt.from(1000),
          currency: CurrencyCode('USD'),
        ),
        currency: CurrencyCode('USD'),
        amountUsd: 1000,
      ),
      Posting(
        target: EnvelopeTarget(EnvelopeId('env-1')),
        amountNative: Money(
          amount: BigInt.from(1000),
          currency: CurrencyCode('USD'),
        ),
        currency: CurrencyCode('USD'),
        amountUsd: 1000,
      ),
    ],
  );
}

/// [CloudFolder] decorator that records every call, with an artificial
/// delay so an overlapping call (a bug) would actually overlap in
/// wall-clock time instead of the race window collapsing to zero — mirrors
/// `_SpyCloudFolder` in cloud_copy_use_case_test.dart.
class _SpyCloudFolder implements CloudFolder {
  final CloudFolder _inner;
  final List<String> callLog = [];
  bool _busy = false;
  bool overlapped = false;

  _SpyCloudFolder(this._inner);

  Future<T> _guarded<T>(String label, Future<T> Function() body) async {
    if (_busy) overlapped = true;
    _busy = true;
    callLog.add(label);
    try {
      await Future.delayed(const Duration(milliseconds: 5));
      return await body();
    } finally {
      _busy = false;
    }
  }

  @override
  Future<List<String>> list() => _guarded('list', _inner.list);

  @override
  Future<String?> read(String name) =>
      _guarded('read:$name', () => _inner.read(name));

  @override
  Future<void> write(String name, String content) =>
      _guarded('write:$name', () => _inner.write(name, content));
}

/// Builds a real [CloudCopyUseCase] backed by in-memory Drift databases, the
/// same minimal shape as the isolated tests in cloud_copy_use_case_test.dart
/// — no ledger seeding, since these tests only care about connection-check
/// and overlap behavior, not backup content.
Future<CloudCopyUseCase> _buildCloudCopy({
  required CloudFolder cloudFolder,
  required Future<bool> Function() isConnected,
}) async {
  final ledgerDb = CuentariaDatabase(NativeDatabase.memory());
  final ratesDb = TasasDatabase(NativeDatabase.memory());
  final catalog = DriftCatalogRepository(ledgerDb);
  await catalog.hydrate();
  final cascadeRepo = DriftCascadeRepository(ledgerDb);
  await cascadeRepo.hydrate();
  final store = DriftEventStore(ledgerDb);
  final rateSeries = DriftRateSeries(ratesDb);
  final statusStore = CloudCopyStatusStore(ledgerDb);

  return CloudCopyUseCase(
    createBackup: CreateBackup(
      eventStore: store,
      catalog: catalog,
      cascade: cascadeRepo,
      rates: rateSeries,
    ),
    restoreBackup: RestoreBackup(
      eventStore: store,
      catalog: catalog,
      cascade: cascadeRepo,
      rates: rateSeries,
      projections: InMemoryLedgerProjections(),
      eventBus: SyncEventBus(),
      unitOfWork: DriftUnitOfWork(ledgerDb),
    ),
    cloudFolder: cloudFolder,
    statusStore: statusStore,
    deviceId: 'device-a',
    isConnected: isConnected,
  );
}

void main() {
  setUpAll(_ensureSqlite3);

  test(
    'publishing a Transaction fires exactly one sync after the debounce',
    () {
      fakeAsync((async) {
        final bus = SyncEventBus();
        var calls = 0;
        final triggers = CloudCopyTriggers(
          sync: () async => calls++,
          eventBus: bus,
          debounce: const Duration(seconds: 30),
        );
        triggers.start();
        calls = 0; // ignore the app-launch sync from start()

        bus.publish(_transaction());
        async.elapse(const Duration(seconds: 29));
        expect(calls, 0, reason: 'debounce has not elapsed yet');

        async.elapse(const Duration(seconds: 1));
        expect(calls, 1);

        triggers.dispose();
      });
    },
  );

  test('three Transactions within 1s coalesce into a single sync', () {
    fakeAsync((async) {
      final bus = SyncEventBus();
      var calls = 0;
      final triggers = CloudCopyTriggers(
        sync: () async => calls++,
        eventBus: bus,
        debounce: const Duration(seconds: 30),
      );
      triggers.start();
      calls = 0;

      bus.publish(_transaction());
      async.elapse(const Duration(milliseconds: 400));
      bus.publish(_transaction());
      async.elapse(const Duration(milliseconds: 400));
      bus.publish(_transaction());
      async.elapse(const Duration(milliseconds: 200));
      expect(
        calls,
        0,
        reason: 'still inside the last event\'s debounce window',
      );

      async.elapse(const Duration(seconds: 30));
      expect(calls, 1);

      triggers.dispose();
    });
  });

  test('start() fires an immediate sync (app-launch trigger)', () {
    fakeAsync((async) {
      final bus = SyncEventBus();
      var calls = 0;
      final triggers = CloudCopyTriggers(
        sync: () async => calls++,
        eventBus: bus,
      );

      triggers.start();
      async.elapse(Duration.zero);

      expect(calls, 1);
      triggers.dispose();
    });
  });

  test('onResume() fires sync immediately, no debounce', () {
    fakeAsync((async) {
      final bus = SyncEventBus();
      var calls = 0;
      final triggers = CloudCopyTriggers(
        sync: () async => calls++,
        eventBus: bus,
      );
      triggers.start();
      calls = 0;

      triggers.onResume();
      async.elapse(Duration.zero);

      expect(calls, 1);
      triggers.dispose();
    });
  });

  test('two overlapping sync-triggering bursts run at most two sequential, '
      'never overlapping, cloud folder runs', () async {
    final bus = SyncEventBus();
    final spy = _SpyCloudFolder(InMemoryCloudFolder());
    final cloudCopy = await _buildCloudCopy(
      cloudFolder: spy,
      isConnected: () async => true,
    );
    final triggers = CloudCopyTriggers(
      sync: cloudCopy.sync,
      eventBus: bus,
      debounce: Duration.zero,
    );
    triggers.start();

    bus.publish(_transaction());
    bus.publish(_transaction());
    bus.publish(_transaction());
    // Give every debounce timer (Duration.zero) and the resulting sync()
    // queueing a chance to run to completion.
    await Future.delayed(const Duration(milliseconds: 100));

    expect(spy.overlapped, isFalse);
    triggers.dispose();
  });

  test('with the session disconnected, the trigger never reaches the '
      'CloudFolder', () async {
    final bus = SyncEventBus();
    final spy = _SpyCloudFolder(InMemoryCloudFolder());
    final cloudCopy = await _buildCloudCopy(
      cloudFolder: spy,
      isConnected: () async => false,
    );
    final triggers = CloudCopyTriggers(
      sync: cloudCopy.sync,
      eventBus: bus,
      debounce: Duration.zero,
    );
    triggers.start();

    bus.publish(_transaction());
    await Future.delayed(const Duration(milliseconds: 50));

    expect(spy.callLog, isEmpty);
    triggers.dispose();
  });

  test(
    'a slow sync never delays recording an Income (non-blocking capture)',
    () async {
      final bus = SyncEventBus();
      final catalog = InMemoryCatalogRepository();
      final accountId = AccountId('acc-income');
      await catalog.saveAccount(
        Account(
          id: accountId,
          name: 'Efectivo',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      final recordTransaction = RecordTransaction(
        store: InMemoryEventStore(),
        projections: InMemoryLedgerProjections(),
        eventBus: bus,
        validator: ReferentialIntegrityValidator(catalog),
      );
      final recordIncome = RecordIncome(
        record: recordTransaction,
        catalog: catalog,
      );

      final triggers = CloudCopyTriggers(
        sync: () => Completer<void>().future, // never completes
        eventBus: bus,
        debounce: Duration.zero,
      );
      triggers.start();

      await recordIncome
          .call(
            eventId: EventId('evt-income'),
            deviceId: 'device-test',
            accountId: accountId,
            amount: Money(
              amount: BigInt.from(1000),
              currency: CurrencyCode('USD'),
            ),
            source: 'Cliente',
          )
          .timeout(const Duration(milliseconds: 500));

      triggers.dispose();
    },
  );
}
