import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:cuentaria_app/features/capture/ui/screens/quick_add_expense_sheet.dart';
import 'package:cuentaria_app/features/distribution/ui/screens/distribute_screen.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_kernel/shared_kernel.dart';

Future<ProviderContainer> _openSheet(
  WidgetTester tester, {
  ProviderContainer? existing,
  bool withRouter = false,
}) async {
  final container =
      existing ??
      ProviderContainer(overrides: [isWebProvider.overrideWithValue(true)]);
  addTearDown(container.dispose);

  if (withRouter) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder:
              (context, state) => Scaffold(
                floatingActionButton: FloatingActionButton(
                  key: const Key('openSheetButton'),
                  onPressed:
                      () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (context) => const QuickAddExpenseSheet(),
                      ),
                  child: const Icon(Icons.add),
                ),
              ),
        ),
        GoRoute(
          path: '/distribute',
          builder: (context, state) => const DistributeScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
  } else {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder:
                (context) => Scaffold(
                  floatingActionButton: FloatingActionButton(
                    key: const Key('openSheetButton'),
                    onPressed:
                        () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          builder: (context) => const QuickAddExpenseSheet(),
                        ),
                    child: const Icon(Icons.add),
                  ),
                ),
          ),
        ),
      ),
    );
  }

  await tester.tap(find.byKey(const Key('openSheetButton')));
  await tester.pumpAndSettle();
  return container;
}

Future<void> _saveAccount(
  ProviderContainer container,
  String id,
  String currency,
) async {
  final catalog = await container.read(catalogRepositoryProvider.future);
  await catalog.saveAccount(
    Account(
      id: AccountId(id),
      name: id,
      nativeCurrency: CurrencyCode(currency),
      isArchived: false,
      updatedAt: DateTime.now(),
    ),
  );
}

Future<void> _enterAmount(WidgetTester tester, String digits) async {
  for (final digit in digits.split('')) {
    await tester.tap(find.byKey(Key('keypadDigit_$digit')));
  }
  await tester.pump();
}

void main() {
  group('QuickAddExpenseSheet — Ingreso', () {
    testWidgets('switching to Ingreso shows the income form', (tester) async {
      await _openSheet(tester);
      await tester.tap(find.byKey(const Key('captureModeIngreso')));
      await tester.pump();

      expect(find.byKey(const Key('incomeSourceField')), findsOneWidget);
    });

    testWidgets(
      'saving a \$500 income from Cliente X posts to Stage, shows the '
      'distribute CTA and suggests the source for the next income',
      (tester) async {
        final container = ProviderContainer(
          overrides: [isWebProvider.overrideWithValue(true)],
        );
        addTearDown(container.dispose);
        await _saveAccount(container, 'acc-usd', 'USD');

        await _openSheet(tester, existing: container, withRouter: true);
        await tester.tap(find.byKey(const Key('captureModeIngreso')));
        await tester.pump();

        await tester.tap(find.byKey(const Key('incomeAccountChip_acc-usd')));
        await tester.enterText(
          find.byKey(const Key('incomeSourceField')),
          'Cliente X',
        );
        await _enterAmount(tester, '50000');

        await tester.ensureVisible(find.byKey(const Key('quickAddSaveButton')));
        await tester.tap(find.byKey(const Key('quickAddSaveButton')));
        await tester.pumpAndSettle();

        final catalog = await container.read(catalogRepositoryProvider.future);
        final projections = container.read(ledgerProjectionsProvider);
        final stageId = catalog.getSystemEnvelope(EnvelopeRole.stage);
        expect(projections.envelopeUsdBalance(stageId), 50000);
        expect(projections.accountBalance(AccountId('acc-usd')).usd, 50000);

        expect(find.textContaining('Sin asignar: \$500.00'), findsOneWidget);
        expect(
          find.byKey(const Key('incomeSourceSuggestion_Cliente X')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('incomeDistributeCta')));
        await tester.pumpAndSettle();

        expect(find.byType(DistributeScreen), findsOneWidget);
      },
    );

    testWidgets(
      'income account chips show currency so accounts with the same name '
      'are distinguishable (#118)',
      (tester) async {
        final container = ProviderContainer(
          overrides: [isWebProvider.overrideWithValue(true)],
        );
        addTearDown(container.dispose);
        final catalog = await container.read(catalogRepositoryProvider.future);
        await catalog.saveAccount(
          Account(
            id: AccountId('acc-usd'),
            name: 'Bancamiga',
            nativeCurrency: CurrencyCode('USD'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );
        await catalog.saveAccount(
          Account(
            id: AccountId('acc-ves'),
            name: 'Bancamiga',
            nativeCurrency: CurrencyCode('VES'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        await _openSheet(tester, existing: container);
        await tester.tap(find.byKey(const Key('captureModeIngreso')));
        await tester.pump();

        expect(find.text('Bancamiga · USD'), findsOneWidget);
        expect(find.text('Bancamiga · VES'), findsOneWidget);
      },
    );

    testWidgets(
      'income mode never surfaces an envelope selector — income always '
      'targets Stage by design (#98/#99)',
      (tester) async {
        final container = ProviderContainer(
          overrides: [isWebProvider.overrideWithValue(true)],
        );
        addTearDown(container.dispose);
        await _saveAccount(container, 'acc-usd', 'USD');
        final catalog = await container.read(catalogRepositoryProvider.future);
        await catalog.saveEnvelope(
          Envelope(
            id: EnvelopeId('env-food'),
            name: 'Food',
            role: EnvelopeRole.none,
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        await _openSheet(tester, existing: container);

        // Sanity check: Gasto mode does show an envelope chip for this
        // envelope, proving the finder below would catch one if Ingreso had
        // it too.
        expect(find.byKey(const Key('envelopeChip_env-food')), findsOneWidget);

        await tester.tap(find.byKey(const Key('captureModeIngreso')));
        await tester.pump();

        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'envelopeChip_',
                ),
          ),
          findsNothing,
        );
      },
    );
  });

  group('QuickAddExpenseSheet — Mover', () {
    testWidgets('switching to Mover shows the account pickers', (tester) async {
      await _openSheet(tester);
      await tester.tap(find.byKey(const Key('captureModeMover')));
      await tester.pump();

      expect(find.byKey(const Key('moverStep1')), findsOneWidget);
    });

    testWidgets(
      'mover source/destination chips show currency, and the amount shows '
      'the source account currency (#118)',
      (tester) async {
        final container = ProviderContainer(
          overrides: [isWebProvider.overrideWithValue(true)],
        );
        addTearDown(container.dispose);
        await _saveAccount(container, 'binance', 'USD');
        await _saveAccount(container, 'bdv', 'VES');

        await _openSheet(tester, existing: container);
        await tester.tap(find.byKey(const Key('captureModeMover')));
        await tester.pump();

        expect(find.text('binance · USD'), findsNWidgets(2));
        expect(find.text('bdv · VES'), findsNWidgets(2));

        await tester.tap(find.byKey(const Key('moverSourceChip_binance')));
        await tester.pump();

        expect(
          tester.widget<Text>(find.byKey(const Key('amountCurrency'))).data,
          'USD',
        );
      },
    );

    testWidgets(
      'Facebank -> Zinli (USD -> USD) shows one amount field and posts a '
      'transfer',
      (tester) async {
        final container = ProviderContainer(
          overrides: [isWebProvider.overrideWithValue(true)],
        );
        addTearDown(container.dispose);
        await _saveAccount(container, 'facebank', 'USD');
        await _saveAccount(container, 'zinli', 'USD');

        await _openSheet(tester, existing: container);
        await tester.tap(find.byKey(const Key('captureModeMover')));
        await tester.pump();

        await tester.tap(find.byKey(const Key('moverSourceChip_facebank')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('moverDestinationChip_zinli')));
        await tester.pump();

        expect(find.byKey(const Key('moverToggleReceived')), findsNothing);

        await _enterAmount(tester, '2000');

        await tester.ensureVisible(find.byKey(const Key('quickAddSaveButton')));
        await tester.tap(find.byKey(const Key('quickAddSaveButton')));
        await tester.pumpAndSettle();

        final store = await container.read(eventStoreProvider.future);
        final log = await store.queryLog();
        expect(log.single.metadata.type, 'Transfer');

        final projections = container.read(ledgerProjectionsProvider);
        expect(projections.accountBalance(AccountId('facebank')).usd, -2000);
        expect(projections.accountBalance(AccountId('zinli')).usd, 2000);
      },
    );

    testWidgets(
      'Binance -> BdV (USD -> VES) unfolds two sides; typing the received '
      'Bs amount derives the rate and posts a conversion with no rate '
      'field stored',
      (tester) async {
        final container = ProviderContainer(
          overrides: [isWebProvider.overrideWithValue(true)],
        );
        addTearDown(container.dispose);
        await _saveAccount(container, 'binance', 'USD');
        await _saveAccount(container, 'bdv', 'VES');

        await _openSheet(tester, existing: container);
        await tester.tap(find.byKey(const Key('captureModeMover')));
        await tester.pump();

        await tester.tap(find.byKey(const Key('moverSourceChip_binance')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('moverDestinationChip_bdv')));
        await tester.pump();

        await _enterAmount(tester, '10000'); // $100.00 given

        expect(find.byKey(const Key('moverToggleReceived')), findsOneWidget);
        expect(find.byKey(const Key('moverToggleRate')), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('moverRateInputField')),
          '4000',
        ); // 4000.00 Bs received
        await tester.pump();

        expect(find.textContaining('40.00'), findsOneWidget); // derived rate

        await tester.ensureVisible(find.byKey(const Key('quickAddSaveButton')));
        await tester.tap(find.byKey(const Key('quickAddSaveButton')));
        await tester.pumpAndSettle();

        final store = await container.read(eventStoreProvider.future);
        final log = await store.queryLog();
        final tx = log.single;
        expect(tx.metadata.type, 'AcquisitionConversion');
        expect(tx.postings.length, 2);
        expect(tx.postings.last.rateRef, '40.00 VES/USD');

        final projections = container.read(ledgerProjectionsProvider);
        expect(
          projections.accountBalance(AccountId('bdv')).native.amount,
          BigInt.from(400000),
        );
      },
    );

    testWidgets(
      'selecting the same account for Desde and Hacia keeps Save disabled',
      (tester) async {
        final container = ProviderContainer(
          overrides: [isWebProvider.overrideWithValue(true)],
        );
        addTearDown(container.dispose);
        await _saveAccount(container, 'facebank', 'USD');

        await _openSheet(tester, existing: container);
        await tester.tap(find.byKey(const Key('captureModeMover')));
        await tester.pump();

        await tester.tap(find.byKey(const Key('moverSourceChip_facebank')));
        await tester.pump();
        await tester.tap(
          find.byKey(const Key('moverDestinationChip_facebank')),
        );
        await tester.pump();

        await _enterAmount(tester, '2000');

        await tester.ensureVisible(find.byKey(const Key('quickAddSaveButton')));
        final saveButton = tester.widget<ElevatedButton>(
          find.byKey(const Key('quickAddSaveButton')),
        );
        expect(saveButton.onPressed, isNull);
      },
    );

    testWidgets('toggling to rate mode pre-fills the derived rate, preserving '
        'consistency', (tester) async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);
      await _saveAccount(container, 'binance', 'USD');
      await _saveAccount(container, 'bdv', 'VES');

      await _openSheet(tester, existing: container);
      await tester.tap(find.byKey(const Key('captureModeMover')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('moverSourceChip_binance')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('moverDestinationChip_bdv')));
      await tester.pump();
      await _enterAmount(tester, '10000'); // $100.00 given

      await tester.enterText(
        find.byKey(const Key('moverRateInputField')),
        '4000',
      );
      await tester.pump();

      await tester.ensureVisible(find.byKey(const Key('moverToggleRate')));
      await tester.tap(find.byKey(const Key('moverToggleRate')));
      await tester.pump();

      final field = tester.widget<TextField>(
        find.byKey(const Key('moverRateInputField')),
      );
      expect(field.controller!.text, '40.00');
    });
  });
}
