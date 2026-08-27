/// Integration tests for [CloudCopyUseCase] (issue #222, ADR-0023): real
/// Drift databases (`NativeDatabase.memory()`) throughout, an
/// [InMemoryCloudFolder] standing in for the user's Google Drive app
/// folder — no mocking of the domain machinery [CloudCopyUseCase]
/// orchestrates (`CreateBackup`, `RestoreBackup`, the cascade engine).
library;

import 'dart:ffi';
import 'dart:io';

import 'package:backup/backup.dart';
import 'package:backup/infrastructure/in_memory_cloud_folder.dart';
import 'package:contabilidad/application/cascade/cascade.dart';
import 'package:contabilidad/application/cascade/cascade_step.dart';
import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/ledger/factories/record_distribution.dart';
import 'package:contabilidad/application/ledger/factories/record_income.dart';
import 'package:contabilidad/application/ledger/factories/record_realization.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:contabilidad/application/cascade/distribute_from_stage.dart';
import 'package:contabilidad/infrastructure/cascade/drift_cascade_repository.dart';
import 'package:contabilidad/infrastructure/catalog/drift_catalog_repository.dart';
import 'package:contabilidad/infrastructure/database/cloud_copy_status_store.dart';
import 'package:contabilidad/infrastructure/database/cuentaria_database.dart';
import 'package:contabilidad/infrastructure/database/drift_event_store.dart';
import 'package:contabilidad/infrastructure/database/drift_unit_of_work.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:cuentaria_app/features/backup/application/create_backup.dart';
import 'package:cuentaria_app/features/backup/application/restore_backup.dart';
import 'package:cuentaria_app/features/cloud_copy/application/cloud_copy_use_case.dart';
import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:event_bus/event_bus.dart';
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

final _usdId = AccountId('acc-usd');
final _vesId = AccountId('acc-ves');
final _rentId = EnvelopeId('env-alquiler');
final _variosId = EnvelopeId('env-varios');

/// One device's full stack, wired the same way the app's composition root
/// would — plus the [CloudCopyUseCase] under test.
class _Device {
  final CuentariaDatabase ledgerDb;
  final TasasDatabase ratesDb;
  final DriftCatalogRepository catalog;
  final DriftCascadeRepository cascadeRepo;
  final DriftEventStore store;
  final InMemoryLedgerProjections projections;
  final DriftRateSeries rateSeries;
  final RecordIncome recordIncome;
  final RecordRealization recordRealization;
  final DistributeFromStage distributor;
  final CreateBackup createBackup;
  final RestoreBackup restoreBackup;
  final CloudCopyStatusStore statusStore;
  final CloudCopyUseCase cloudCopy;

  _Device({
    required this.ledgerDb,
    required this.ratesDb,
    required this.catalog,
    required this.cascadeRepo,
    required this.store,
    required this.projections,
    required this.rateSeries,
    required this.recordIncome,
    required this.recordRealization,
    required this.distributor,
    required this.createBackup,
    required this.restoreBackup,
    required this.statusStore,
    required this.cloudCopy,
  });

  Future<void> close() async {
    await ledgerDb.close();
    await ratesDb.close();
  }
}

Future<_Device> _openDevice(
  String deviceId,
  CloudFolder folder, {
  DateTime Function()? now,
}) async {
  final ledgerDb = CuentariaDatabase(NativeDatabase.memory());
  final ratesDb = TasasDatabase(NativeDatabase.memory());

  final catalog = DriftCatalogRepository(ledgerDb);
  await catalog.hydrate();
  final cascadeRepo = DriftCascadeRepository(ledgerDb);
  await cascadeRepo.hydrate();
  final store = DriftEventStore(ledgerDb);
  final projections = InMemoryLedgerProjections();
  final bus = SyncEventBus();
  final validator = ReferentialIntegrityValidator(catalog);
  final recordTx = RecordTransaction(
    store: store,
    projections: projections,
    eventBus: bus,
    validator: validator,
  );
  final rateSeries = DriftRateSeries(ratesDb);
  final statusStore = CloudCopyStatusStore(ledgerDb);

  final createBackup = CreateBackup(
    eventStore: store,
    catalog: catalog,
    cascade: cascadeRepo,
    rates: rateSeries,
    now: now,
  );
  final restoreBackup = RestoreBackup(
    eventStore: store,
    catalog: catalog,
    cascade: cascadeRepo,
    rates: rateSeries,
    projections: projections,
    eventBus: bus,
    unitOfWork: DriftUnitOfWork(
      ledgerDb,
      onRollback: [catalog.hydrate, cascadeRepo.hydrate],
    ),
  );

  return _Device(
    ledgerDb: ledgerDb,
    ratesDb: ratesDb,
    catalog: catalog,
    cascadeRepo: cascadeRepo,
    store: store,
    projections: projections,
    rateSeries: rateSeries,
    recordIncome: RecordIncome(record: recordTx, catalog: catalog),
    recordRealization: RecordRealization(
      record: recordTx,
      catalog: catalog,
      projections: projections,
    ),
    distributor: DistributeFromStage(
      projections: projections,
      catalog: catalog,
      cascadeRepo: cascadeRepo,
      recordDistribution: RecordDistribution(
        record: recordTx,
        catalog: catalog,
      ),
    ),
    createBackup: createBackup,
    restoreBackup: restoreBackup,
    statusStore: statusStore,
    cloudCopy: CloudCopyUseCase(
      createBackup: createBackup,
      restoreBackup: restoreBackup,
      cloudFolder: folder,
      statusStore: statusStore,
      deviceId: deviceId,
      now: now,
    ),
  );
}

/// Seeds a small multi-currency ledger with a two-step cascade: Ingreso
/// $1.000,00 (USD), a cascade splitting it into a $200 fixed rent step and a
/// catch-all, then a Bs. 4.000,00 gasto at a 40 VES/USD rate.
Future<void> _seedMultiCurrencyLedger(_Device d) async {
  await d.catalog.saveAccount(
    Account(
      id: _usdId,
      name: 'Efectivo',
      nativeCurrency: CurrencyCode('USD'),
      isArchived: false,
      updatedAt: DateTime.utc(2026, 1, 1),
    ),
  );
  await d.catalog.saveAccount(
    Account(
      id: _vesId,
      name: 'BdV',
      nativeCurrency: CurrencyCode('VES'),
      isArchived: false,
      updatedAt: DateTime.utc(2026, 1, 1),
    ),
  );
  await d.catalog.saveEnvelope(
    Envelope(
      id: _rentId,
      name: 'Alquiler',
      role: EnvelopeRole.none,
      isArchived: false,
      updatedAt: DateTime.utc(2026, 1, 1),
    ),
  );
  await d.catalog.saveEnvelope(
    Envelope(
      id: _variosId,
      name: 'Varios',
      role: EnvelopeRole.none,
      isArchived: false,
      updatedAt: DateTime.utc(2026, 1, 1),
    ),
  );

  await d.cascadeRepo.save(
    Cascade(
      steps: [
        CascadeStep.fixed(envelopeId: _rentId, amountUsd: 20000),
        CascadeStep.catchAll(envelopeId: _variosId),
      ],
      updatedAt: DateTime.utc(2026, 1, 1),
    ),
  );

  await d.recordIncome.call(
    eventId: EventId('evt-income-usd'),
    deviceId: 'dev-a',
    accountId: _usdId,
    amount: Money(amount: BigInt.from(100000), currency: CurrencyCode('USD')),
    source: 'Cliente',
    occurredAt: DomainTimestamp(DateTime.utc(2026, 1, 2)),
  );

  await d.distributor.apply(
    eventId: EventId('evt-distribute'),
    deviceId: 'dev-a',
    amount: 100000,
  );

  await d.recordRealization.foreignCurrencyExpense(
    eventId: EventId('evt-expense-ves'),
    deviceId: 'dev-a',
    accountId: _vesId,
    destinationEnvelopeId: _variosId,
    nativeAmount: Money(
      amount: BigInt.from(400000),
      currency: CurrencyCode('VES'),
    ),
    currentRate: Decimal.parse('40.00'),
    occurredAt: DomainTimestamp(DateTime.utc(2026, 1, 3)),
  );
}

/// [CloudFolder] decorator that records every call, with an artificial
/// delay so overlapping calls (a bug) would actually overlap in wall-clock
/// time instead of the race window collapsing to zero.
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

/// [CloudFolder] decorator whose [write] always fails, simulating a
/// provider outage (ADR-0023 §8) — [list]/[read] pass through untouched.
class _WriteFailsCloudFolder implements CloudFolder {
  final CloudFolder _inner;
  _WriteFailsCloudFolder(this._inner);

  @override
  Future<List<String>> list() => _inner.list();

  @override
  Future<String?> read(String name) => _inner.read(name);

  @override
  Future<void> write(String name, String content) =>
      throw const CloudUnavailable('sin internet');
}

void main() {
  setUpAll(_ensureSqlite3);

  test(
    'push writes <device_id>.ndjson byte-identical to CreateBackup',
    () async {
      final folder = InMemoryCloudFolder();
      final a = await _openDevice(
        'device-a',
        folder,
        now: () => DateTime.utc(2026, 1, 20),
      );
      await _seedMultiCurrencyLedger(a);

      await a.cloudCopy.push();

      final expected = await a.createBackup.call();
      expect(await folder.read('device-a.ndjson'), equals(expected.content));
      expect(await folder.list(), equals(['device-a.ndjson']));

      await a.close();
    },
  );

  test(
    'sync merges two devices: patrimonio and cascade end up identical',
    () async {
      final folder = InMemoryCloudFolder();
      final a = await _openDevice('device-a', folder);
      final b = await _openDevice('device-b', folder);
      await _seedMultiCurrencyLedger(a);

      await a.cloudCopy.sync();
      await b.cloudCopy.sync();

      for (final id in a.catalog.accountIds) {
        expect(
          b.projections.accountBalance(id).usd,
          equals(a.projections.accountBalance(id).usd),
          reason: 'account ${id.value} usd balance',
        );
        expect(
          b.projections.accountBalance(id).native.amount,
          equals(a.projections.accountBalance(id).native.amount),
          reason: 'account ${id.value} native balance',
        );
      }
      for (final envelope in a.catalog.envelopes) {
        expect(
          b.projections.envelopeUsdBalance(envelope.id),
          equals(a.projections.envelopeUsdBalance(envelope.id)),
          reason: 'envelope ${envelope.id.value} usd balance',
        );
      }

      final aCascade = await a.cascadeRepo.load();
      final bCascade = await b.cascadeRepo.load();
      expect(bCascade, isNotNull);
      expect(bCascade!.steps, hasLength(aCascade!.steps.length));
      for (var i = 0; i < aCascade.steps.length; i++) {
        expect(
          bCascade.steps[i].envelopeId,
          equals(aCascade.steps[i].envelopeId),
        );
        expect(
          bCascade.steps[i].runtimeType,
          equals(aCascade.steps[i].runtimeType),
        );
      }

      await a.close();
      await b.close();
    },
  );

  test('sync repeated three times is idempotent', () async {
    final folder = InMemoryCloudFolder();
    final a = await _openDevice('device-a', folder);
    final b = await _openDevice('device-b', folder);
    await _seedMultiCurrencyLedger(a);

    await a.cloudCopy.sync();
    await b.cloudCopy.sync();

    final eventCount = (await b.store.queryLog()).length;
    final usdBalance = b.projections.accountBalance(_usdId).usd;
    final vesBalance = b.projections.accountBalance(_vesId).usd;

    await b.cloudCopy.sync();
    await b.cloudCopy.sync();

    expect((await b.store.queryLog()).length, equals(eventCount));
    expect(b.projections.accountBalance(_usdId).usd, equals(usdBalance));
    expect(b.projections.accountBalance(_vesId).usd, equals(vesBalance));

    await a.close();
    await b.close();
  });

  test('a broken foreign file does not change the base, names itself and its '
      'line in lastError, and a healthy foreign file still gets in', () async {
    final folder = InMemoryCloudFolder();
    final healthyMarkerId = AccountId('acc-healthy-marker');
    final brokenMarkerId = AccountId('acc-broken-marker');

    final healthy = await _openDevice('device-healthy', folder);
    await healthy.catalog.saveAccount(
      Account(
        id: healthyMarkerId,
        name: 'Healthy',
        nativeCurrency: CurrencyCode('USD'),
        isArchived: false,
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );
    await healthy.cloudCopy.push();

    // A second, would-be device whose Backup File is corrupted before it
    // ever reaches the folder — its own marker account must never surface
    // on the target.
    final broken = await _openDevice('device-broken', InMemoryCloudFolder());
    await broken.catalog.saveAccount(
      Account(
        id: brokenMarkerId,
        name: 'Broken',
        nativeCurrency: CurrencyCode('USD'),
        isArchived: false,
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );
    final brokenBackup = await broken.createBackup.call();
    final brokenLines = brokenBackup.content.split('\n');
    // Corrupt the account line without changing the line count, so this
    // is an InvalidLine, not a TruncatedFile.
    final accountLineIndex = brokenLines.indexWhere(
      (l) => l.contains('"kind":"account"'),
    );
    brokenLines[accountLineIndex] = '{not valid json';
    await folder.write('device-broken.ndjson', brokenLines.join('\n'));

    final target = await _openDevice('device-target', folder);
    await target.cloudCopy.pull();

    expect(target.catalog.getAccount(healthyMarkerId), isNotNull);
    expect(target.catalog.getAccount(brokenMarkerId), isNull);
    expect(target.cloudCopy.status.lastError, contains('device-broken.ndjson'));
    expect(
      target.cloudCopy.status.lastError,
      contains('renglón ${accountLineIndex + 1}'),
    );

    await healthy.close();
    await broken.close();
    await target.close();
  });

  test('a CloudUnavailable on write is recorded with its cause, without '
      'touching lastSuccessAt, while lastAttemptAt does update', () async {
    final folder = _WriteFailsCloudFolder(InMemoryCloudFolder());
    final ledgerDb = CuentariaDatabase(NativeDatabase.memory());
    final ratesDb = TasasDatabase(NativeDatabase.memory());
    final catalog = DriftCatalogRepository(ledgerDb);
    await catalog.hydrate();
    final cascadeRepo = DriftCascadeRepository(ledgerDb);
    await cascadeRepo.hydrate();
    final store = DriftEventStore(ledgerDb);
    final rateSeries = DriftRateSeries(ratesDb);
    final statusStore = CloudCopyStatusStore(ledgerDb);
    final createBackup = CreateBackup(
      eventStore: store,
      catalog: catalog,
      cascade: cascadeRepo,
      rates: rateSeries,
    );
    final restoreBackup = RestoreBackup(
      eventStore: store,
      catalog: catalog,
      cascade: cascadeRepo,
      rates: rateSeries,
      projections: InMemoryLedgerProjections(),
      eventBus: SyncEventBus(),
      unitOfWork: DriftUnitOfWork(ledgerDb),
    );
    final cloudCopy = CloudCopyUseCase(
      createBackup: createBackup,
      restoreBackup: restoreBackup,
      cloudFolder: folder,
      statusStore: statusStore,
      deviceId: 'device-a',
    );

    await cloudCopy.push();

    expect(cloudCopy.status.lastError, contains('sin internet'));
    expect(cloudCopy.status.lastSuccessAt, isNull);
    expect(cloudCopy.status.lastAttemptAt, isNotNull);
    expect(await statusStore.getLastSuccessAt(), isNull);
    expect(await statusStore.getLastError(), contains('sin internet'));

    await ledgerDb.close();
    await ratesDb.close();
  });

  test('two concurrent sync() calls run at most two sequential, never '
      'overlapping, cloud folder runs; a third is discarded', () async {
    final spy = _SpyCloudFolder(InMemoryCloudFolder());
    final a = await _openDevice('device-a', spy);

    await Future.wait([
      a.cloudCopy.sync(),
      a.cloudCopy.sync(),
      a.cloudCopy.sync(),
    ]);

    expect(spy.overlapped, isFalse);
    final listCalls = spy.callLog.where((c) => c == 'list').length;
    expect(listCalls, lessThanOrEqualTo(2));
    expect(listCalls, greaterThanOrEqualTo(1));

    await a.close();
  });

  test('sync() never calls the cloud folder when not connected', () async {
    final spy = _SpyCloudFolder(InMemoryCloudFolder());
    final ledgerDb = CuentariaDatabase(NativeDatabase.memory());
    final ratesDb = TasasDatabase(NativeDatabase.memory());
    final catalog = DriftCatalogRepository(ledgerDb);
    await catalog.hydrate();
    final cascadeRepo = DriftCascadeRepository(ledgerDb);
    await cascadeRepo.hydrate();
    final store = DriftEventStore(ledgerDb);
    final rateSeries = DriftRateSeries(ratesDb);
    final statusStore = CloudCopyStatusStore(ledgerDb);
    final cloudCopy = CloudCopyUseCase(
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
      cloudFolder: spy,
      statusStore: statusStore,
      deviceId: 'device-a',
      isConnected: () async => false,
    );

    await cloudCopy.sync();

    expect(spy.callLog, isEmpty);

    await ledgerDb.close();
    await ratesDb.close();
  });

  test(
    'status persists across recreating the use case on the same base',
    () async {
      final folder = InMemoryCloudFolder();
      final ledgerDb = CuentariaDatabase(NativeDatabase.memory());
      final ratesDb = TasasDatabase(NativeDatabase.memory());
      final catalog = DriftCatalogRepository(ledgerDb);
      await catalog.hydrate();
      final cascadeRepo = DriftCascadeRepository(ledgerDb);
      await cascadeRepo.hydrate();
      final store = DriftEventStore(ledgerDb);
      final rateSeries = DriftRateSeries(ratesDb);
      final statusStore = CloudCopyStatusStore(ledgerDb);
      final createBackup = CreateBackup(
        eventStore: store,
        catalog: catalog,
        cascade: cascadeRepo,
        rates: rateSeries,
      );
      final restoreBackup = RestoreBackup(
        eventStore: store,
        catalog: catalog,
        cascade: cascadeRepo,
        rates: rateSeries,
        projections: InMemoryLedgerProjections(),
        eventBus: SyncEventBus(),
        unitOfWork: DriftUnitOfWork(ledgerDb),
      );

      final first = CloudCopyUseCase(
        createBackup: createBackup,
        restoreBackup: restoreBackup,
        cloudFolder: folder,
        statusStore: statusStore,
        deviceId: 'device-a',
      );
      await first.push();
      expect(first.status.lastSuccessAt, isNotNull);

      final second = CloudCopyUseCase(
        createBackup: createBackup,
        restoreBackup: restoreBackup,
        cloudFolder: folder,
        statusStore: statusStore,
        deviceId: 'device-a',
      );
      await second.hydrate();

      expect(second.status.lastSuccessAt, equals(first.status.lastSuccessAt));
      expect(second.status.lastError, equals(first.status.lastError));

      await ledgerDb.close();
      await ratesDb.close();
    },
  );
}
