/// Shared test scaffolding for the Cloud Copy UI (issue #223): builds a
/// [CloudCopyUseCase] wired the way the app's composition root does, in
/// memory except for the status store — mirrors the device stack in
/// `cloud_copy_use_case_test.dart` (issue #222).
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:backup/backup.dart';
import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/application/ledger/factories/record_income.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:contabilidad/infrastructure/cascade/in_memory_cascade_repository.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:contabilidad/infrastructure/database/cloud_copy_status_store.dart';
import 'package:contabilidad/infrastructure/database/cuentaria_database.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:contabilidad/infrastructure/in_memory_unit_of_work.dart';
import 'package:cuentaria_app/features/backup/application/create_backup.dart';
import 'package:cuentaria_app/features/backup/application/restore_backup.dart';
import 'package:cuentaria_app/features/cloud_copy/application/cloud_copy_use_case.dart';
import 'package:cuentaria_app/features/cloud_copy/application/google_drive_session.dart';
import 'package:drift/native.dart';
import 'package:event_bus/event_bus.dart';
import 'package:sqlite3/open.dart';
import 'package:tasas/infrastructure/in_memory/in_memory_rate_series.dart';

void ensureSqlite3ForTests() {
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

CloudCopyUseCase buildTestCloudCopyUseCase({
  required CloudFolder cloudFolder,
  Future<bool> Function()? isConnected,
  DateTime Function()? now,
  String deviceId = 'device-test',
}) =>
    buildTestCloudCopyDevice(
      cloudFolder: cloudFolder,
      isConnected: isConnected,
      now: now,
      deviceId: deviceId,
    ).useCase;

/// A [CloudCopyUseCase] plus enough of its device stack to seed a local
/// movement (via [recordIncome]) and inspect the catalog after a pull (via
/// [catalog]) — needed by the merge-notice tests (issue #226, ADR-0023 §6),
/// which have to tell "device with data" apart from "device empty".
class TestCloudCopyDevice {
  final CloudCopyUseCase useCase;
  final CatalogRepository catalog;
  final RecordIncome recordIncome;

  const TestCloudCopyDevice({
    required this.useCase,
    required this.catalog,
    required this.recordIncome,
  });
}

TestCloudCopyDevice buildTestCloudCopyDevice({
  required CloudFolder cloudFolder,
  Future<bool> Function()? isConnected,
  DateTime Function()? now,
  String deviceId = 'device-test',
}) {
  final eventStore = InMemoryEventStore();
  final catalog = InMemoryCatalogRepository();
  final cascade = InMemoryCascadeRepository();
  final rates = InMemoryRateSeries();
  final createBackup = CreateBackup(
    eventStore: eventStore,
    catalog: catalog,
    cascade: cascade,
    rates: rates,
    now: now,
  );
  final restoreBackup = RestoreBackup(
    eventStore: eventStore,
    catalog: catalog,
    cascade: cascade,
    rates: rates,
    projections: InMemoryLedgerProjections(),
    eventBus: SyncEventBus(),
    unitOfWork: const InMemoryUnitOfWork(),
  );
  final statusStore = CloudCopyStatusStore(
    CuentariaDatabase(NativeDatabase.memory()),
  );
  final recordTransaction = RecordTransaction(
    store: eventStore,
    projections: InMemoryLedgerProjections(),
    eventBus: SyncEventBus(),
    validator: ReferentialIntegrityValidator(catalog),
  );
  return TestCloudCopyDevice(
    useCase: CloudCopyUseCase(
      createBackup: createBackup,
      restoreBackup: restoreBackup,
      cloudFolder: cloudFolder,
      statusStore: statusStore,
      deviceId: deviceId,
      isConnected: isConnected ?? (() async => true),
      now: now,
    ),
    catalog: catalog,
    recordIncome: RecordIncome(record: recordTransaction, catalog: catalog),
  );
}

/// A [CloudFolder] whose every call fails with [CloudUnavailable] — the
/// "modo de demo" for the error state (issue #223 AC #4).
class FailingCloudFolder implements CloudFolder {
  const FailingCloudFolder([this.reason = 'sin internet']);

  final String reason;

  @override
  Future<List<String>> list() async => throw CloudUnavailable(reason);

  @override
  Future<String?> read(String name) async => throw CloudUnavailable(reason);

  @override
  Future<void> write(String name, String content) async =>
      throw CloudUnavailable(reason);
}

/// A [CloudFolder] whose [write] waits on a swappable [Completer] — lets a
/// test observe the "Copiando…" in-progress state before letting a sync
/// finish (issue #223 AC #3). Starts resolved so a first sync (e.g. the one
/// `onConnect` triggers) completes normally; call [pause] right before the
/// sync under test, then [resume] once the in-progress state was observed.
class CompleterCloudFolder implements CloudFolder {
  Completer<void> _writeGate = Completer<void>()..complete();

  @override
  Future<List<String>> list() async => [];

  @override
  Future<String?> read(String name) async => null;

  @override
  Future<void> write(String name, String content) => _writeGate.future;

  void pause() => _writeGate = Completer<void>();

  void resume() => _writeGate.complete();
}

/// Test double for [GoogleDriveSession] (issue #225): [connect]/[disconnect]
/// just flip local state, no real Google Sign-In round trip. [accountEmail]
/// is fixed to `'cuenta de prueba'`, matching the simulated session it
/// replaces so existing screen assertions keep reading the same text.
class FakeGoogleDriveSession implements GoogleDriveSession {
  FakeGoogleDriveSession([this._token]);

  String? _token;
  bool disconnectCalled = false;

  @override
  bool get isConnected => _token != null;

  @override
  String? get accountEmail => isConnected ? 'cuenta de prueba' : null;

  @override
  Future<void> connect() async {
    _token = 'fake-token';
  }

  @override
  Future<void> disconnect() async {
    disconnectCalled = true;
    _token = null;
  }

  @override
  Future<String> accessToken() async {
    final token = _token;
    if (token == null) throw const CloudUnavailable('sin sesión de Google');
    return token;
  }
}
