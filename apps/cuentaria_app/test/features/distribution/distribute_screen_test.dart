import 'package:contabilidad/application/cascade/cascade.dart';
import 'package:contabilidad/application/cascade/cascade_step.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/ledger/factories/record_opening.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:cuentaria_app/features/distribution/ui/screens/distribute_screen.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:cuentaria_app/providers/ledger_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
        accountId: catalog.accountIds.first,
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
        accountId: catalog.accountIds.first,
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
}
