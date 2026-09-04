/// Tests for [CloudCopyUseCase.hasPendingMerge] (issue #226, ADR-0023 §6):
/// the "se van a juntar" warning is a connect-time decision — true only when
/// this device already has events *and* the cloud folder already has
/// another device's file.
library;

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
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:contabilidad/infrastructure/in_memory_unit_of_work.dart';
import 'package:cuentaria_app/features/backup/application/create_backup.dart';
import 'package:cuentaria_app/features/backup/application/restore_backup.dart';
import 'package:cuentaria_app/features/cloud_copy/application/cloud_copy_use_case.dart';
import 'package:drift/native.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/infrastructure/in_memory/in_memory_rate_series.dart';

import 'cloud_copy_test_support.dart';

const _deviceId = 'device-under-test';
final _accountId = AccountId('acc-usd');

Future<CloudCopyUseCase> _buildUseCase({
  required CloudFolder cloudFolder,
  bool seedLocalEvent = false,
}) async {
  final eventStore = InMemoryEventStore();
  final catalog = InMemoryCatalogRepository();
  final cascade = InMemoryCascadeRepository();
  final rates = InMemoryRateSeries();

  if (seedLocalEvent) {
    await catalog.saveAccount(
      Account(
        id: _accountId,
        name: 'Efectivo',
        nativeCurrency: CurrencyCode('USD'),
        isArchived: false,
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );
    final recordTransaction = RecordTransaction(
      store: eventStore,
      projections: InMemoryLedgerProjections(),
      eventBus: SyncEventBus(),
      validator: ReferentialIntegrityValidator(catalog),
    );
    await RecordIncome(record: recordTransaction, catalog: catalog).call(
      eventId: EventId('evt-local'),
      deviceId: _deviceId,
      accountId: _accountId,
      amount: Money(amount: BigInt.from(100000), currency: CurrencyCode('USD')),
      source: 'Cliente',
    );
  }

  final createBackup = CreateBackup(
    eventStore: eventStore,
    catalog: catalog,
    cascade: cascade,
    rates: rates,
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

  return CloudCopyUseCase(
    createBackup: createBackup,
    restoreBackup: restoreBackup,
    cloudFolder: cloudFolder,
    statusStore: CloudCopyStatusStore(
      CuentariaDatabase(NativeDatabase.memory()),
    ),
    deviceId: _deviceId,
  );
}

void main() {
  setUpAll(ensureSqlite3ForTests);

  test('false when both the device and the cloud are empty', () async {
    final useCase = await _buildUseCase(cloudFolder: InMemoryCloudFolder());

    expect(await useCase.hasPendingMerge(), isFalse);
  });

  test('false when the device is empty, even with a foreign file in the '
      'cloud', () async {
    final folder = InMemoryCloudFolder({'device-other.ndjson': 'irrelevant'});
    final useCase = await _buildUseCase(cloudFolder: folder);

    expect(await useCase.hasPendingMerge(), isFalse);
  });

  test('false when the device has data but the cloud is empty', () async {
    final useCase = await _buildUseCase(
      cloudFolder: InMemoryCloudFolder(),
      seedLocalEvent: true,
    );

    expect(await useCase.hasPendingMerge(), isFalse);
  });

  test('false when the cloud only has this device\'s own file', () async {
    final folder = InMemoryCloudFolder({'$_deviceId.ndjson': 'stale'});
    final useCase = await _buildUseCase(
      cloudFolder: folder,
      seedLocalEvent: true,
    );

    expect(await useCase.hasPendingMerge(), isFalse);
  });

  test(
    'true when the device has data and the cloud has a foreign file',
    () async {
      final folder = InMemoryCloudFolder({'device-other.ndjson': 'irrelevant'});
      final useCase = await _buildUseCase(
        cloudFolder: folder,
        seedLocalEvent: true,
      );

      expect(await useCase.hasPendingMerge(), isTrue);
    },
  );
}
