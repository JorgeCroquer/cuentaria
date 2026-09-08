/// Antidote e2e for issue #297 (ADR-0023 §6, third occurrence of this class
/// of bug after #226/#241): the "se van a juntar" merge gate must live
/// inside `CloudCopyUseCase.sync()`, not the screen. The bug was a race —
/// `connect()` resolves, the screen shows the merge dialog and awaits the
/// user, but `CloudCopyTriggers.onResume()` (F3.5, #224) fires `sync()`
/// directly on the very next resume (e.g. coming back from the Google
/// account picker), gated only by `isConnected` — so the pull happened while
/// the dialog was still on screen, before the user ever answered.
///
/// This test exercises the real [CloudCopyUseCase] and real
/// [CloudCopyTriggers] together — no screen, no hand-rolled harness — the
/// same composition-root shape as
/// `e2e_f3_cloud_copy_two_device_cascade_faithful_test.dart`: whatever calls
/// `sync()` (a resume, a debounced Transaction, the eventual explicit call)
/// must be blocked by the same gate until consent is persisted.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:backup/backup.dart';
import 'package:backup/infrastructure/in_memory_cloud_folder.dart';
import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/ledger/factories/record_income.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:contabilidad/infrastructure/cascade/in_memory_cascade_repository.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:contabilidad/infrastructure/database/cloud_copy_status_store.dart';
import 'package:contabilidad/infrastructure/database/cuentaria_database.dart';
import 'package:contabilidad/infrastructure/database/merge_consent_provider.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:contabilidad/infrastructure/in_memory_unit_of_work.dart';
import 'package:cuentaria_app/features/backup/application/create_backup.dart';
import 'package:cuentaria_app/features/backup/application/restore_backup.dart';
import 'package:cuentaria_app/features/cloud_copy/application/cloud_copy_triggers.dart';
import 'package:cuentaria_app/features/cloud_copy/application/cloud_copy_use_case.dart';
import 'package:drift/native.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:sqlite3/open.dart';
import 'package:tasas/infrastructure/in_memory/in_memory_rate_series.dart';

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

DateTime _fakeNow() => DateTime.utc(2026, 9, 8);

/// Lets a `CloudCopyTriggers`-fired sync (debounce is [Duration.zero] in
/// this test) actually run before the next assertion — mirrors
/// `e2e_f3_cloud_copy_two_device_cascade_faithful_test.dart`.
Future<void> _waitForDebounce() =>
    Future<void>.delayed(const Duration(milliseconds: 1));

/// Stands in for the real Google Drive session's connected state — mutable
/// so [_Device.connect]/[_Device.disconnect] can flip it, the same shape
/// `isConnected` closures use throughout the Cloud Copy tests.
class _ConnectionState {
  bool connected = false;
}

class _Device {
  final CuentariaDatabase ledgerDb;
  final InMemoryCatalogRepository catalog;
  final InMemoryEventStore store;
  final RecordIncome recordIncome;
  final CloudCopyUseCase cloudCopy;
  final CloudCopyTriggers triggers;
  final _ConnectionState _connection;

  _Device({
    required this.ledgerDb,
    required this.catalog,
    required this.store,
    required this.recordIncome,
    required this.cloudCopy,
    required this.triggers,
    required _ConnectionState connection,
  }) : _connection = connection;

  void connect() => _connection.connected = true;
  void disconnect() => _connection.connected = false;

  Future<void> close() async {
    triggers.dispose();
    await ledgerDb.close();
  }
}

Future<_Device> _openDevice(String deviceId, CloudFolder folder) async {
  final eventStore = InMemoryEventStore();
  final catalog = InMemoryCatalogRepository();
  final cascade = InMemoryCascadeRepository();
  final rates = InMemoryRateSeries();
  final bus = SyncEventBus();
  final projections = InMemoryLedgerProjections();
  final validator = ReferentialIntegrityValidator(catalog);
  final recordTx = RecordTransaction(
    store: eventStore,
    projections: projections,
    eventBus: bus,
    validator: validator,
  );

  final createBackup = CreateBackup(
    eventStore: eventStore,
    catalog: catalog,
    cascade: cascade,
    rates: rates,
    now: _fakeNow,
  );
  final restoreBackup = RestoreBackup(
    eventStore: eventStore,
    catalog: catalog,
    cascade: cascade,
    rates: rates,
    projections: projections,
    eventBus: bus,
    unitOfWork: const InMemoryUnitOfWork(),
  );

  final ledgerDb = CuentariaDatabase(NativeDatabase.memory());
  final statusStore = CloudCopyStatusStore(ledgerDb);
  final mergeConsent = MergeConsentProvider(ledgerDb);
  final connection = _ConnectionState();

  final cloudCopy = CloudCopyUseCase(
    createBackup: createBackup,
    restoreBackup: restoreBackup,
    cloudFolder: folder,
    statusStore: statusStore,
    deviceId: deviceId,
    isConnected: () async => connection.connected,
    getMergeConsent: mergeConsent.hasConsent,
    setMergeConsent: mergeConsent.setConsent,
    now: _fakeNow,
  );

  return _Device(
    ledgerDb: ledgerDb,
    catalog: catalog,
    store: eventStore,
    recordIncome: RecordIncome(record: recordTx, catalog: catalog),
    cloudCopy: cloudCopy,
    triggers: CloudCopyTriggers(
      sync: cloudCopy.sync,
      eventBus: bus,
      debounce: Duration.zero,
    ),
    connection: connection,
  );
}

Future<void> _seedAccountAndIncome(
  _Device device, {
  required AccountId id,
  required String name,
  required String eventId,
}) async {
  await device.catalog.saveAccount(
    Account(
      id: id,
      name: name,
      nativeCurrency: CurrencyCode('USD'),
      isArchived: false,
      updatedAt: DateTime.utc(2026, 1, 1),
    ),
  );
  await device.recordIncome.call(
    eventId: EventId(eventId),
    deviceId: 'seed',
    accountId: id,
    amount: Money(amount: BigInt.from(100000), currency: CurrencyCode('USD')),
    source: 'Cliente',
  );
}

void main() {
  setUpAll(_ensureSqlite3);

  test('cancelling the merge dialog leaves the local log and catalog untouched '
      'through resumes and transactions; accepting merges; a later relaunch '
      'does not re-prompt (#297, ADR-0023 §6)', () async {
    final folder = InMemoryCloudFolder();

    // ---------------------------------------------------------------
    // Old backups already in the cloud, from a device that isn't this
    // one — mirrors "conectó Drive con respaldos viejos en la nube".
    // ---------------------------------------------------------------
    final foreign = await _openDevice('device-foreign', folder);
    await _seedAccountAndIncome(
      foreign,
      id: AccountId('acc-foreign'),
      name: 'Efectivo viejo',
      eventId: 'evt-foreign',
    );
    foreign.connect();
    await foreign.cloudCopy.push();
    expect(await folder.list(), equals(['device-foreign.ndjson']));

    // ---------------------------------------------------------------
    // This device already has its own movements — "arrancó y entró
    // algunos movimientos" before ever touching Cloud Copy.
    // ---------------------------------------------------------------
    final local = await _openDevice('device-local', folder);
    await _seedAccountAndIncome(
      local,
      id: AccountId('acc-local'),
      name: 'Efectivo',
      eventId: 'evt-local',
    );
    final eventCountBeforeConnect = (await local.store.queryLog()).length;

    // ---------------------------------------------------------------
    // Connect: the trigger's app-launch sync hits the gate — nothing
    // pulled, status says it's waiting on the user.
    // ---------------------------------------------------------------
    local.connect();
    local.triggers.start();
    await _waitForDebounce();

    expect(local.cloudCopy.status.waitingForMergeConsent, isTrue);
    expect(local.catalog.accounts, hasLength(1));
    expect(local.catalog.getAccount(AccountId('acc-foreign')), isNull);
    expect(
      (await local.store.queryLog()).length,
      equals(eventCountBeforeConnect),
    );

    // ---------------------------------------------------------------
    // Scenario 1 — the race: a resume fires *while the dialog would
    // still be on screen* (e.g. coming back from the Google account
    // picker), plus a Transaction recorded during that same window.
    // Neither must sneak the foreign history in.
    // ---------------------------------------------------------------
    local.triggers.onResume();
    await _waitForDebounce();

    expect(local.cloudCopy.status.waitingForMergeConsent, isTrue);
    expect(local.catalog.accounts, hasLength(1));

    await local.recordIncome.call(
      eventId: EventId('evt-local-during-dialog'),
      deviceId: 'device-local',
      accountId: AccountId('acc-local'),
      amount: Money(amount: BigInt.from(500), currency: CurrencyCode('USD')),
      source: 'Cliente',
    );
    await _waitForDebounce();

    expect(
      local.cloudCopy.status.waitingForMergeConsent,
      isTrue,
      reason: 'a Transaction during the dialog still must not clear the gate',
    );
    expect(local.catalog.accounts, hasLength(1));
    expect(local.catalog.getAccount(AccountId('acc-foreign')), isNull);

    // ---------------------------------------------------------------
    // Cancelar: disconnects without ever consenting. More resumes
    // afterwards still must not merge.
    // ---------------------------------------------------------------
    local.disconnect();
    final eventCountAfterCancel = (await local.store.queryLog()).length;

    local.triggers.onResume();
    await _waitForDebounce();
    local.triggers.onResume();
    await _waitForDebounce();

    expect(local.catalog.accounts, hasLength(1));
    expect(local.catalog.getAccount(AccountId('acc-foreign')), isNull);
    expect(
      (await local.store.queryLog()).length,
      equals(eventCountAfterCancel),
    );
    expect(await local.cloudCopy.getMergeConsent(), isFalse);

    // ---------------------------------------------------------------
    // Scenario 2 — reconnect and accept: consent is persisted first,
    // then sync() actually merges.
    // ---------------------------------------------------------------
    local.connect();
    await local.cloudCopy.setMergeConsent(true);
    await local.cloudCopy.sync();

    expect(local.cloudCopy.status.waitingForMergeConsent, isFalse);
    expect(local.catalog.accounts, hasLength(2));
    expect(local.catalog.getAccount(AccountId('acc-foreign')), isNotNull);

    // ---------------------------------------------------------------
    // Scenario 3 — a later relaunch: a brand new CloudCopyUseCase (as
    // a fresh app launch would build) reads the same persisted
    // ledgerDb, so it never re-prompts even though hasPendingMerge is
    // still structurally true.
    // ---------------------------------------------------------------
    final relaunchedMergeConsent = MergeConsentProvider(local.ledgerDb);
    final relaunchedStatusStore = CloudCopyStatusStore(local.ledgerDb);
    final relaunchedCloudCopy = CloudCopyUseCase(
      createBackup: CreateBackup(
        eventStore: local.store,
        catalog: local.catalog,
        cascade: InMemoryCascadeRepository(),
        rates: InMemoryRateSeries(),
        now: _fakeNow,
      ),
      restoreBackup: RestoreBackup(
        eventStore: local.store,
        catalog: local.catalog,
        cascade: InMemoryCascadeRepository(),
        rates: InMemoryRateSeries(),
        projections: InMemoryLedgerProjections(),
        eventBus: SyncEventBus(),
        unitOfWork: const InMemoryUnitOfWork(),
      ),
      cloudFolder: folder,
      statusStore: relaunchedStatusStore,
      deviceId: 'device-local',
      isConnected: () async => true,
      getMergeConsent: relaunchedMergeConsent.hasConsent,
      setMergeConsent: relaunchedMergeConsent.setConsent,
      now: _fakeNow,
    );

    await relaunchedCloudCopy.sync();

    expect(relaunchedCloudCopy.status.waitingForMergeConsent, isFalse);
    expect(local.catalog.accounts, hasLength(2));

    await foreign.close();
    await local.close();
  });
}
