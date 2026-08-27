/// Shared test scaffolding for the Cloud Copy UI (issue #223): builds a
/// [CloudCopyUseCase] wired the way the app's composition root does, in
/// memory except for the status store — mirrors the device stack in
/// `cloud_copy_use_case_test.dart` (issue #222).
library;

import 'dart:ffi';
import 'dart:io';

import 'package:backup/backup.dart';
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
  return CloudCopyUseCase(
    createBackup: createBackup,
    restoreBackup: restoreBackup,
    cloudFolder: cloudFolder,
    statusStore: statusStore,
    deviceId: deviceId,
    isConnected: isConnected ?? (() async => true),
    now: now,
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
