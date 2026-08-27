/// Widget tests for the "se van a juntar" merge notice on the Cloud Copy
/// screen (issue #226, ADR-0023 §6): the three branches a connect can take —
/// pull silently, push silently, or warn first — driven by two independent
/// [TestCloudCopyDevice]s sharing one [InMemoryCloudFolder], the same shape
/// `cloud_copy_use_case_test.dart` uses for its two-device scenarios.
library;

import 'package:backup/infrastructure/in_memory_cloud_folder.dart';
import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:cuentaria_app/features/cloud_copy/application/cloud_copy_providers.dart';
import 'package:cuentaria_app/features/cloud_copy/ui/screens/cloud_copy_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';

import 'cloud_copy_test_support.dart';

Future<void> _pumpScreen(
  WidgetTester tester, {
  required dynamic override,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [override],
      child: const MaterialApp(home: CloudCopyScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _seedAccountAndIncome(
  TestCloudCopyDevice device, {
  required AccountId id,
  required String name,
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
    eventId: EventId('evt-${id.value}'),
    deviceId: 'seed',
    accountId: id,
    amount: Money(amount: BigInt.from(100000), currency: CurrencyCode('USD')),
    source: 'Cliente',
  );
}

void main() {
  setUpAll(ensureSqlite3ForTests);

  testWidgets('an empty device connecting to a cloud with a foreign file pulls '
      'without asking', (tester) async {
    final folder = InMemoryCloudFolder();
    final foreign = buildTestCloudCopyDevice(
      cloudFolder: folder,
      deviceId: 'device-foreign',
    );
    await _seedAccountAndIncome(
      foreign,
      id: AccountId('acc-foreign'),
      name: 'Efectivo',
    );
    await foreign.useCase.push();

    final local = buildTestCloudCopyDevice(
      cloudFolder: folder,
      deviceId: 'device-local',
    );

    await _pumpScreen(
      tester,
      override: cloudCopyUseCaseProvider.overrideWith(
        (ref) async => local.useCase,
      ),
    );

    await tester.tap(find.byKey(const Key('connectGoogleDriveButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mergeDialog')), findsNothing);
    expect(local.catalog.accounts, hasLength(1));
    expect(local.catalog.getAccount(AccountId('acc-foreign')), isNotNull);
  });

  testWidgets(
    'a device with a movement connecting to a cloud with a foreign file '
    'shows the merge warning; Cancelar stays disconnected and untouched, '
    'reconnecting and tapping Juntar merges both',
    (tester) async {
      final folder = InMemoryCloudFolder();
      final foreign = buildTestCloudCopyDevice(
        cloudFolder: folder,
        deviceId: 'device-foreign',
      );
      await _seedAccountAndIncome(
        foreign,
        id: AccountId('acc-foreign'),
        name: 'Efectivo',
      );
      await foreign.useCase.push();

      final local = buildTestCloudCopyDevice(
        cloudFolder: folder,
        deviceId: 'device-local',
      );
      await _seedAccountAndIncome(
        local,
        id: AccountId('acc-local'),
        name: 'Efectivo',
      );

      await _pumpScreen(
        tester,
        override: cloudCopyUseCaseProvider.overrideWith(
          (ref) async => local.useCase,
        ),
      );

      await tester.tap(find.byKey(const Key('connectGoogleDriveButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mergeDialog')), findsOneWidget);
      expect(
        find.text(
          'Este aparato ya tiene movimientos. Se van a juntar con los de tu '
          'nube; si creaste las mismas cuentas en los dos, vas a verlas '
          'repetidas.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('cancelMergeButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mergeDialog')), findsNothing);
      expect(find.text('Conectar mi Google Drive'), findsOneWidget);
      expect(local.catalog.accounts, hasLength(1));
      expect(local.catalog.getAccount(AccountId('acc-foreign')), isNull);

      await tester.tap(find.byKey(const Key('connectGoogleDriveButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mergeDialog')), findsOneWidget);

      await tester.tap(find.byKey(const Key('confirmMergeButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mergeDialog')), findsNothing);
      expect(local.catalog.accounts, hasLength(2));
      expect(
        local.catalog.accounts.where((a) => a.name == 'Efectivo'),
        hasLength(2),
      );
    },
  );

  testWidgets(
    'a device with data connecting to an empty cloud pushes without asking',
    (tester) async {
      final folder = InMemoryCloudFolder();
      final local = buildTestCloudCopyDevice(
        cloudFolder: folder,
        deviceId: 'device-local',
      );
      await _seedAccountAndIncome(
        local,
        id: AccountId('acc-local'),
        name: 'Efectivo',
      );

      await _pumpScreen(
        tester,
        override: cloudCopyUseCaseProvider.overrideWith(
          (ref) async => local.useCase,
        ),
      );

      await tester.tap(find.byKey(const Key('connectGoogleDriveButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mergeDialog')), findsNothing);
      expect(await folder.list(), contains('device-local.ndjson'));
    },
  );
}
