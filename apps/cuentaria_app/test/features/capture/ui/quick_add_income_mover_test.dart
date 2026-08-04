import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
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

Future<void> _backspace(WidgetTester tester, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.tap(find.byKey(const Key('keypadBackspace')));
  }
  await tester.pump();
}

/// Funds [accountId] with [nativeAmount] at a frozen cost of [usdAmount],
/// via a bare Opening posting pair, so a balance/cost basis exists without
/// going through a capture flow.
Future<void> _fund(
  ProviderContainer container, {
  required String accountId,
  required BigInt nativeAmount,
  required CurrencyCode currency,
  required int usdAmount,
}) async {
  final store = await container.read(eventStoreProvider.future);
  final catalog = await container.read(catalogRepositoryProvider.future);
  final projections = container.read(ledgerProjectionsProvider);
  final differentialId = catalog.getSystemEnvelope(EnvelopeRole.differential);
  final eventId = EventId('evt-fund-$accountId');
  await store.append(
    Transaction.create(
      metadata: TransactionMetadata(
        eventId: eventId,
        type: 'Opening',
        occurredAt: DomainTimestamp(DateTime.now().toUtc()),
        recordedAt: DomainTimestamp(DateTime.now().toUtc()),
        deviceId: 'dev-1',
        schemaVersion: 1,
      ),
      postings: [
        Posting(
          target: AccountTarget(AccountId(accountId)),
          amountNative: Money(amount: nativeAmount, currency: currency),
          currency: currency,
          amountUsd: usdAmount,
        ),
        Posting(
          target: EnvelopeTarget(differentialId),
          amountNative: Money(
            amount: BigInt.from(usdAmount),
            currency: CurrencyCode('USD'),
          ),
          currency: CurrencyCode('USD'),
          amountUsd: usdAmount,
        ),
      ],
    ),
  );
  projections.apply((await store.get(eventId))!);
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
      'BdV -> Binance (VES -> USD) unfolds two sides; typing the received '
      'USD amount derives the rate labeled VES/USD (not USD/USD) and posts '
      'a DisposalConversion (#116)',
      (tester) async {
        final container = ProviderContainer(
          overrides: [isWebProvider.overrideWithValue(true)],
        );
        addTearDown(container.dispose);
        await _saveAccount(container, 'bdv', 'VES');
        await _saveAccount(container, 'binance', 'USD');

        await _openSheet(tester, existing: container);
        await tester.tap(find.byKey(const Key('captureModeMover')));
        await tester.pump();

        await tester.tap(find.byKey(const Key('moverSourceChip_bdv')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('moverDestinationChip_binance')));
        await tester.pump();

        await _enterAmount(tester, '400000'); // 4000.00 Bs given

        expect(find.byKey(const Key('moverToggleReceived')), findsOneWidget);
        expect(find.byKey(const Key('moverToggleRate')), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('moverRateInputField')),
          '100', // $100.00 received
        );
        await tester.pump();

        // Derived rate must read the foreign side of the pair (VES), not
        // the USD destination (#116, point 3/5 of the fix).
        expect(find.text('Tasa: 40.00 VES/USD'), findsOneWidget);

        await tester.ensureVisible(find.byKey(const Key('quickAddSaveButton')));
        await tester.tap(find.byKey(const Key('quickAddSaveButton')));
        await tester.pumpAndSettle();

        final store = await container.read(eventStoreProvider.future);
        final log = await store.queryLog();
        final tx = log.single;
        expect(tx.metadata.type, 'DisposalConversion');
        final destinationPosting = tx.postings.firstWhere(
          (p) => p.target == AccountTarget(AccountId('binance')),
        );
        expect(destinationPosting.amountUsd, 10000);
        expect(destinationPosting.rateRef, '40.00 VES/USD');

        final projections = container.read(ledgerProjectionsProvider);
        expect(projections.accountBalance(AccountId('binance')).usd, 10000);
      },
    );

    testWidgets(
      'BdV -> Binance (VES -> USD) in rate mode labels the field VES/USD '
      'and derives the received USD via deriveUsdCents (#116)',
      (tester) async {
        final container = ProviderContainer(
          overrides: [isWebProvider.overrideWithValue(true)],
        );
        addTearDown(container.dispose);
        await _saveAccount(container, 'bdv', 'VES');
        await _saveAccount(container, 'binance', 'USD');

        await _openSheet(tester, existing: container);
        await tester.tap(find.byKey(const Key('captureModeMover')));
        await tester.pump();

        await tester.tap(find.byKey(const Key('moverSourceChip_bdv')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('moverDestinationChip_binance')));
        await tester.pump();

        await _enterAmount(tester, '400000'); // 4000.00 Bs given

        await tester.ensureVisible(find.byKey(const Key('moverToggleRate')));
        await tester.tap(find.byKey(const Key('moverToggleRate')));
        await tester.pump();

        final field = tester.widget<TextField>(
          find.byKey(const Key('moverRateInputField')),
        );
        expect(field.decoration!.labelText, 'Tasa aplicada (VES/USD)');

        await tester.enterText(
          find.byKey(const Key('moverRateInputField')),
          '40',
        );
        await tester.pump();

        expect(find.text('Recibes: 100.00 USD'), findsOneWidget);

        await tester.ensureVisible(find.byKey(const Key('quickAddSaveButton')));
        await tester.tap(find.byKey(const Key('quickAddSaveButton')));
        await tester.pumpAndSettle();

        final projections = container.read(ledgerProjectionsProvider);
        expect(projections.accountBalance(AccountId('binance')).usd, 10000);
      },
    );

    testWidgets(
      'a foreign-currency source disables destination chips in a different '
      'foreign currency — that pair cannot be formed (ADR-0018 §5, #116)',
      (tester) async {
        final container = ProviderContainer(
          overrides: [isWebProvider.overrideWithValue(true)],
        );
        addTearDown(container.dispose);
        await _saveAccount(container, 'bdv', 'VES');
        await _saveAccount(container, 'binance', 'USD');
        await _saveAccount(container, 'binance-eur', 'EUR');

        await _openSheet(tester, existing: container);
        await tester.tap(find.byKey(const Key('captureModeMover')));
        await tester.pump();

        await tester.tap(find.byKey(const Key('moverSourceChip_bdv')));
        await tester.pump();

        final eurChip = tester.widget<ChoiceChip>(
          find.byKey(const Key('moverDestinationChip_binance-eur')),
        );
        expect(eurChip.onSelected, isNull);

        final usdChip = tester.widget<ChoiceChip>(
          find.byKey(const Key('moverDestinationChip_binance')),
        );
        expect(usdChip.onSelected, isNotNull);
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

    testWidgets(
      'BdV -> Bancamiga (VES -> VES): the excess valuation row appears only '
      'once the amount exceeds the known balance, and disappears when the '
      'amount drops back under it (ADR-0018 §3)',
      (tester) async {
        final container = ProviderContainer(
          overrides: [isWebProvider.overrideWithValue(true)],
        );
        addTearDown(container.dispose);
        await _saveAccount(container, 'bdv', 'VES');
        await _saveAccount(container, 'bancamiga', 'VES');
        // 5,000.00 Bs at a frozen cost of $10.00 (200 VES/USD).
        await _fund(
          container,
          accountId: 'bdv',
          nativeAmount: BigInt.from(500000),
          currency: CurrencyCode('VES'),
          usdAmount: 1000,
        );

        await _openSheet(tester, existing: container);
        await tester.tap(find.byKey(const Key('captureModeMover')));
        await tester.pump();

        await tester.tap(find.byKey(const Key('moverSourceChip_bdv')));
        await tester.pump();
        await tester.tap(
          find.byKey(const Key('moverDestinationChip_bancamiga')),
        );
        await tester.pump();

        // Same-currency non-USD Mover: no two-sided rate toggle at all.
        expect(find.byKey(const Key('moverToggleReceived')), findsNothing);

        // 1,000.00 Bs — well under the known 5,000.00 Bs balance.
        await _enterAmount(tester, '100000');
        expect(
          find.byKey(const Key('moverExcessValuationAnnouncement')),
          findsNothing,
        );

        // 20,000.00 Bs — exceeds the balance, no rate registered yet.
        await _backspace(tester, 6);
        await _enterAmount(tester, '2000000');
        expect(
          find.byKey(const Key('moverExcessRateUnavailableMessage')),
          findsOneWidget,
        );

        // Drop back under the balance: the row disappears again.
        await _backspace(tester, 7);
        await _enterAmount(tester, '100000');
        expect(
          find.byKey(const Key('moverExcessValuationAnnouncement')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('moverExcessRateUnavailableMessage')),
          findsNothing,
        );
      },
    );
  });
}
