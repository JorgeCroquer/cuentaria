import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:cuentaria_app/features/distribution/ui/screens/distribute_screen.dart';
import 'package:cuentaria_app/features/patrimonio/ui/screens/patrimonio_screen.dart';
import 'package:cuentaria_app/main.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:cuentaria_app/providers/ledger_providers.dart';
import 'package:cuentaria_app/providers/tasas_providers.dart';
import 'package:cuentaria_app/ui/ledger_screen.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';

void main() {
  testWidgets(
    'boots into the Patrimonio tab and Ledger stays reachable via the shell',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [isWebProvider.overrideWithValue(true)],
          child: const MyApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PatrimonioScreen), findsOneWidget);
      expect(find.byType(LedgerScreen), findsNothing);

      await tester.tap(find.text('Ledger'));
      await tester.pumpAndSettle();

      expect(find.byType(LedgerScreen), findsOneWidget);
    },
  );

  testWidgets(
    'header updates after recording an income through the real app, without a reload',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [isWebProvider.overrideWithValue(true)],
          child: const MyApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('realCostAmount'))).data,
        '\$0.00',
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(PatrimonioScreen)),
      );
      final catalog = await container.read(catalogRepositoryProvider.future);
      final deviceId = await container.read(deviceIdProvider.future);
      final recordIncome = await container.read(recordIncomeProvider.future);

      await recordIncome(
        eventId: EventId('evt-integration-1'),
        deviceId: deviceId,
        accountId: catalog.accountIds.first,
        amount: Money(amount: BigInt.from(2500), currency: CurrencyCode('USD')),
        source: 'Manual entry',
      );

      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('realCostAmount'))).data,
        '\$25.00',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('todayValueAmount'))).data,
        '\$25.00',
      );
    },
  );

  testWidgets(
    'shows guidance instead of a spinner or zero when there are no accounts',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isWebProvider.overrideWithValue(true),
            catalogRepositoryProvider.overrideWith(
              (ref) async => InMemoryCatalogRepository(),
            ),
          ],
          child: const MaterialApp(home: PatrimonioScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('patrimonioEmptyState')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('\$0.00'), findsNothing);
    },
  );

  testWidgets(
    'recording rates from a cold app boot appends both observations',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [isWebProvider.overrideWithValue(true)],
          child: const MyApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PatrimonioScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('recordRatesAction')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('bcvRateField')), '37.5');
      await tester.enterText(find.byKey(const Key('paraleloRateField')), '90');
      await tester.tap(find.byKey(const Key('saveRatesButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('bcvRateField')), findsNothing);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(PatrimonioScreen)),
      );
      final series = await container.read(rateSeriesProvider.future);
      final latest = await series.latestFor(CurrencyCode('VES'));
      expect(latest, isNotNull);
      expect(latest!.source, 'manual:paralelo');
      expect(latest.nativePerUsd, Decimal.parse('90'));
    },
  );

  testWidgets(
    'tapping "Sin asignar" from a cold start navigates to the distribute '
    'flow (#83)',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [isWebProvider.overrideWithValue(true)],
          child: const MyApp(),
        ),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(PatrimonioScreen)),
      );
      final catalog = await container.read(catalogRepositoryProvider.future);
      final deviceId = await container.read(deviceIdProvider.future);
      final recordIncome = await container.read(recordIncomeProvider.future);

      await recordIncome(
        eventId: EventId('evt-stage-nav'),
        deviceId: deviceId,
        accountId: catalog.accountIds.first,
        amount: Money(amount: BigInt.from(2000), currency: CurrencyCode('USD')),
        source: 'Manual entry',
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Sin asignar'), findsOneWidget);

      await tester.tap(find.textContaining('Sin asignar'));
      await tester.pumpAndSettle();

      expect(find.byType(DistributeScreen), findsOneWidget);
      expect(find.byKey(const Key('noCascadeMessage')), findsOneWidget);
    },
  );

  testWidgets(
    'Envelopes block lists a user Envelope with GoalLine progress and hides '
    'the Diferencial/Ajustes system Envelopes (#83)',
    (tester) async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      final catalog = await container.read(catalogRepositoryProvider.future);
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

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: PatrimonioScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Vacaciones'), findsOneWidget);
      expect(find.text('Differential'), findsNothing);
      expect(find.text('Adjustments'), findsNothing);
    },
  );
}
