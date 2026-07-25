import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/application/cascade/cascade.dart';
import 'package:contabilidad/application/cascade/cascade_step.dart';
import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/ledger/factories/record_opening.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:cuentaria_app/features/distribution/ui/screens/cascade_editor_screen.dart';
import 'package:cuentaria_app/features/distribution/ui/screens/distribute_screen.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:cuentaria_app/providers/ledger_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_kernel/shared_kernel.dart';

void main() {
  testWidgets(
    'previews and applies the saved cascade, zeroing the Stage balance '
    '(#83)',
    (tester) async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      final catalog = await container.read(catalogRepositoryProvider.future);
      final projections = container.read(ledgerProjectionsProvider);
      final stageId = catalog.getSystemEnvelope(EnvelopeRole.stage);

      final accountId = AccountId('test-acc');
      await catalog.saveAccount(
        Account(
          id: accountId,
          name: 'Test Account',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      final ahorros = EnvelopeId('ahorros');
      await catalog.saveEnvelope(
        Envelope(
          id: ahorros,
          name: 'Ahorros',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      final cascadeRepo = await container.read(
        cascadeRepositoryProvider.future,
      );
      await cascadeRepo.save(
        Cascade(
          steps: [CascadeStep.catchAll(envelopeId: ahorros)],
          updatedAt: DateTime.now(),
        ),
      );

      final deviceId = await container.read(deviceIdProvider.future);
      final recordIncome = await container.read(recordIncomeProvider.future);
      await recordIncome(
        eventId: EventId('evt-fund-stage'),
        deviceId: deviceId,
        accountId: accountId,
        amount: Money(amount: BigInt.from(5000), currency: CurrencyCode('USD')),
        source: 'Manual entry',
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: DistributeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ahorros'), findsOneWidget);
      expect(find.text('\$50.00'), findsOneWidget);

      await tester.tap(find.byKey(const Key('applyDistributionButton')));
      await tester.pumpAndSettle();

      expect(projections.envelopeUsdBalance(stageId), 0);
      expect(projections.envelopeUsdBalance(ahorros), 5000);
    },
  );

  testWidgets(
    'previews and applies the saved cascade from Apertura, zeroing it '
    'without touching Stage (#96)',
    (tester) async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      final catalog = await container.read(catalogRepositoryProvider.future);
      final store = await container.read(eventStoreProvider.future);
      final projections = container.read(ledgerProjectionsProvider);
      final eventBus = container.read(eventBusProvider);
      final deviceId = await container.read(deviceIdProvider.future);
      final aperturaId = catalog.getSystemEnvelope(EnvelopeRole.opening);
      final stageId = catalog.getSystemEnvelope(EnvelopeRole.stage);

      final vacaciones = EnvelopeId('vacaciones');
      await catalog.saveEnvelope(
        Envelope(
          id: vacaciones,
          name: 'Vacaciones',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      final cascadeRepo = await container.read(
        cascadeRepositoryProvider.future,
      );
      await cascadeRepo.save(
        Cascade(
          steps: [CascadeStep.catchAll(envelopeId: vacaciones)],
          updatedAt: DateTime.now(),
        ),
      );

      final recordOpening = RecordOpening(
        record: RecordTransaction(
          store: store,
          projections: projections,
          eventBus: eventBus,
          validator: ReferentialIntegrityValidator(catalog),
        ),
        catalog: catalog,
        projections: projections,
      );
      await recordOpening(
        eventId: EventId('evt-open-1'),
        deviceId: deviceId,
        accountId: await _ensureTestAccount(catalog),
        nativeAmount: Money(
          amount: BigInt.from(1500),
          currency: CurrencyCode('USD'),
        ),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: DistributeScreen(source: EnvelopeRole.opening),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Distribuir Apertura'), findsOneWidget);
      expect(find.text('Vacaciones'), findsOneWidget);
      expect(find.text('\$15.00'), findsOneWidget);

      await tester.tap(find.byKey(const Key('applyDistributionButton')));
      await tester.pumpAndSettle();

      expect(projections.envelopeUsdBalance(aperturaId), 0);
      expect(projections.envelopeUsdBalance(vacaciones), 1500);
      expect(projections.envelopeUsdBalance(stageId), 0);
    },
  );

  testWidgets('editing the cascade via CascadeEditorScreen updates the '
      'distributionPreviewProvider / DistributeScreen (#96)', (tester) async {
    final container = ProviderContainer(
      overrides: [isWebProvider.overrideWithValue(true)],
    );
    addTearDown(container.dispose);

    final catalog = await container.read(catalogRepositoryProvider.future);

    final ahorros = EnvelopeId('ahorros');
    final vacaciones = EnvelopeId('vacaciones');
    await catalog.saveEnvelope(
      Envelope(
        id: ahorros,
        name: 'Ahorros',
        role: EnvelopeRole.none,
        isArchived: false,
        updatedAt: DateTime.now(),
      ),
    );
    await catalog.saveEnvelope(
      Envelope(
        id: vacaciones,
        name: 'Vacaciones',
        role: EnvelopeRole.none,
        isArchived: false,
        updatedAt: DateTime.now(),
      ),
    );

    final cascadeRepo = await container.read(cascadeRepositoryProvider.future);
    await cascadeRepo.save(
      Cascade(
        steps: [CascadeStep.catchAll(envelopeId: ahorros)],
        updatedAt: DateTime.now(),
      ),
    );

    final deviceId = await container.read(deviceIdProvider.future);
    final recordIncome = await container.read(recordIncomeProvider.future);
    await recordIncome(
      eventId: EventId('evt-edit-preview'),
      deviceId: deviceId,
      accountId: await _ensureTestAccount(catalog),
      amount: Money(amount: BigInt.from(5000), currency: CurrencyCode('USD')),
      source: 'Manual entry',
    );

    final router = GoRouter(
      initialLocation: '/distribute',
      routes: [
        GoRoute(
          path: '/distribute',
          builder: (context, state) => const DistributeScreen(),
        ),
        GoRoute(
          path: '/distribute/edit',
          builder: (context, state) => const CascadeEditorScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ahorros'), findsOneWidget);
    expect(find.text('\$50.00'), findsOneWidget);

    await tester.tap(find.byKey(const Key('editCascadeAction')));
    await tester.pumpAndSettle();
    expect(find.byType(CascadeEditorScreen), findsOneWidget);

    // Swap the catch-all step: Ahorros out, Vacaciones in.
    await tester.tap(find.byKey(const Key('deleteCascadeStep_0')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('addCascadeStepButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stepEnvelopeDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vacaciones').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stepFundingTypeDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Catch-all').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saveStepButton')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('saveCascadeButton')));
    await tester.pumpAndSettle();

    expect(find.byType(DistributeScreen), findsOneWidget);
    expect(find.text('Ahorros'), findsNothing);
    expect(find.text('Vacaciones'), findsOneWidget);
    expect(find.text('\$50.00'), findsOneWidget);
  });
}

/// The bootstrap no longer seeds a default Account (#94 removed the "Efectivo"
/// seed once accounts became creatable from the UI), so a test that needs one
/// creates it itself instead of reaching for `accountIds.first`.
Future<AccountId> _ensureTestAccount(CatalogRepository catalog) async {
  if (catalog.accountIds.isNotEmpty) return catalog.accountIds.first;
  final id = AccountId('test-acc');
  await catalog.saveAccount(
    Account(
      id: id,
      name: 'Test Account',
      nativeCurrency: CurrencyCode('USD'),
      isArchived: false,
      updatedAt: DateTime.now(),
    ),
  );
  return id;
}
