import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:cuentaria_app/features/accounts/ui/screens/accounts_screen.dart';
import 'package:cuentaria_app/features/capture/application/capture_providers.dart';
import 'package:cuentaria_app/features/capture/ui/screens/quick_add_expense_sheet.dart';
import 'package:cuentaria_app/features/patrimonio/ui/screens/patrimonio_screen.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:cuentaria_app/providers/tasas_providers.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/domain/rate_observation.dart';

import 'catalog_picker_test_helpers.dart';

Future<ProviderContainer> _openSheet(
  WidgetTester tester, {
  ProviderContainer? existing,
  Size surfaceSize = const Size(800, 1600),
}) async {
  final container =
      existing ??
      ProviderContainer(overrides: [isWebProvider.overrideWithValue(true)]);
  addTearDown(container.dispose);

  // The U2 sheet stacks a mode selector, hero amount, question cards, a
  // date/note row and the keypad (#281) — taller than the default test
  // surface, which would otherwise leave the keypad unscrolled-into-view
  // and its taps landing outside the render tree.
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

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

  await tester.tap(find.byKey(const Key('openSheetButton')));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('QuickAddExpenseSheet', () {
    testWidgets('opens with the keypad visible and Save disabled until an '
        'amount is entered', (tester) async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);
      final catalog = await container.read(catalogRepositoryProvider.future);
      await catalog.saveAccount(
        Account(
          id: AccountId('acc-usd'),
          name: 'USD wallet',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );
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

      expect(find.byKey(const Key('numericKeypad')), findsOneWidget);
      final saveButton = tester.widget<ElevatedButton>(
        find.byKey(const Key('quickAddSaveButton')),
      );
      expect(saveButton.onPressed, isNull);

      await tester.tap(find.byKey(const Key('keypadDigit_5')));
      await tester.pump();

      final enabledSaveButton = tester.widget<ElevatedButton>(
        find.byKey(const Key('quickAddSaveButton')),
      );
      expect(enabledSaveButton.onPressed, isNotNull);
    });

    testWidgets('preselects the last-used account and the most frequent '
        'envelope from ledger history', (tester) async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);
      final catalog = await container.read(catalogRepositoryProvider.future);

      final oldAccount = Account(
        id: AccountId('acc-old'),
        name: 'Old wallet',
        nativeCurrency: CurrencyCode('USD'),
        isArchived: false,
        updatedAt: DateTime.now(),
      );
      final recentAccount = Account(
        id: AccountId('acc-recent'),
        name: 'Recent wallet',
        nativeCurrency: CurrencyCode('USD'),
        isArchived: false,
        updatedAt: DateTime.now(),
      );
      await catalog.saveAccount(oldAccount);
      await catalog.saveAccount(recentAccount);

      final rareEnvelope = Envelope(
        id: EnvelopeId('env-rare'),
        name: 'Rare',
        role: EnvelopeRole.none,
        isArchived: false,
        updatedAt: DateTime.now(),
      );
      final frequentEnvelope = Envelope(
        id: EnvelopeId('env-frequent'),
        name: 'Frequent',
        role: EnvelopeRole.none,
        isArchived: false,
        updatedAt: DateTime.now(),
      );
      await catalog.saveEnvelope(rareEnvelope);
      await catalog.saveEnvelope(frequentEnvelope);

      final useCase = await container.read(
        quickAddExpenseUseCaseProvider.future,
      );
      final deviceId = await container.read(deviceIdProvider.future);
      final money = Money(
        amount: BigInt.from(100),
        currency: CurrencyCode('USD'),
      );

      await useCase(
        eventId: EventId('evt-1'),
        deviceId: deviceId,
        accountId: oldAccount.id,
        envelopeId: rareEnvelope.id,
        amount: money,
        occurredAt: DomainTimestamp(DateTime.utc(2026, 1, 1)),
      );
      await useCase(
        eventId: EventId('evt-2'),
        deviceId: deviceId,
        accountId: recentAccount.id,
        envelopeId: frequentEnvelope.id,
        amount: money,
        occurredAt: DomainTimestamp(DateTime.utc(2026, 1, 2)),
      );
      await useCase(
        eventId: EventId('evt-3'),
        deviceId: deviceId,
        accountId: recentAccount.id,
        envelopeId: frequentEnvelope.id,
        amount: money,
        occurredAt: DomainTimestamp(DateTime.utc(2026, 1, 3)),
      );

      await _openSheet(tester, existing: container);

      expect(
        find.descendant(
          of: find.byKey(const Key('accountField')),
          matching: find.textContaining('Recent wallet'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('envelopeField')),
          matching: find.text('Frequent'),
        ),
        findsOneWidget,
      );

      // Opening the envelope picker shows both in "Frecuentes" (both have
      // history) ordered by descending frequency: frequent (2x) above rare
      // (1x).
      await tester.tap(find.byKey(const Key('envelopeField')));
      await tester.pumpAndSettle();

      final selectedEnvelopeChip = tester.widget<ChoiceChip>(
        find.byKey(const Key('envelopeChip_env-frequent')),
      );
      expect(selectedEnvelopeChip.selected, isTrue);

      final frequentChipCenter = tester.getCenter(
        find.byKey(const Key('envelopeChip_env-frequent')),
      );
      final rareChipCenter = tester.getCenter(
        find.byKey(const Key('envelopeChip_env-rare')),
      );
      expect(frequentChipCenter.dy, lessThan(rareChipCenter.dy));
    });

    testWidgets(
      'account chips show currency so accounts with the same name are '
      'distinguishable (e.g. two "Bancamiga" accounts in different '
      'currencies, #118)',
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
        await tester.tap(find.byKey(const Key('accountField')));
        await tester.pumpAndSettle();

        // One of the two is the default selection, so its label also shows
        // on the (now covered, but still in the tree) field behind the
        // sheet — scope the check to each chip row so that doesn't matter.
        expect(
          find.descendant(
            of: find.byKey(const Key('accountChip_acc-usd')),
            matching: find.text('Bancamiga · USD'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('accountChip_acc-ves')),
            matching: find.text('Bancamiga · VES'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'amount display shows the selected account currency, updating live '
      'as the account chip selection changes (#118)',
      (tester) async {
        final container = ProviderContainer(
          overrides: [isWebProvider.overrideWithValue(true)],
        );
        addTearDown(container.dispose);
        final catalog = await container.read(catalogRepositoryProvider.future);
        await catalog.saveAccount(
          Account(
            id: AccountId('acc-usd'),
            name: 'USD wallet',
            nativeCurrency: CurrencyCode('USD'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );
        await catalog.saveAccount(
          Account(
            id: AccountId('acc-ves'),
            name: 'Bs wallet',
            nativeCurrency: CurrencyCode('VES'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        await _openSheet(tester, existing: container);

        await pickCatalogItem(tester, 'accountChip_acc-usd');
        expect(
          tester.widget<Text>(find.byKey(const Key('amountCurrency'))).data,
          'USD',
        );

        await pickCatalogItem(tester, 'accountChip_acc-ves');
        expect(
          tester.widget<Text>(find.byKey(const Key('amountCurrency'))).data,
          'VES',
        );
      },
    );

    testWidgets('date defaults to today', (tester) async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);
      final catalog = await container.read(catalogRepositoryProvider.future);
      await catalog.saveAccount(
        Account(
          id: AccountId('acc-usd'),
          name: 'USD wallet',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      await _openSheet(tester, existing: container);

      // The hero's secondary line reads "hoy · <short date>" when the
      // capture date is today (U2 redesign, #281).
      expect(find.textContaining('hoy ·'), findsOneWidget);
      expect(find.text('Hoy'), findsOneWidget);
    });

    testWidgets('saving a USD expense posts a plain expense, closes the '
        'sheet and resets for the next capture', (tester) async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);
      final catalog = await container.read(catalogRepositoryProvider.future);
      final account = Account(
        id: AccountId('acc-usd'),
        name: 'USD wallet',
        nativeCurrency: CurrencyCode('USD'),
        isArchived: false,
        updatedAt: DateTime.now(),
      );
      await catalog.saveAccount(account);
      final envelope = Envelope(
        id: EnvelopeId('env-food'),
        name: 'Food',
        role: EnvelopeRole.none,
        isArchived: false,
        updatedAt: DateTime.now(),
      );
      await catalog.saveEnvelope(envelope);

      await _openSheet(tester, existing: container);

      await tester.tap(find.byKey(const Key('keypadDigit_5')));
      await tester.tap(find.byKey(const Key('keypadDigit_0')));
      await tester.tap(find.byKey(const Key('keypadDigit_0')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('quickAddSaveButton')));
      await tester.tap(find.byKey(const Key('quickAddSaveButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('numericKeypad')), findsNothing);

      final projections = container.read(ledgerProjectionsProvider);
      expect(projections.accountBalance(account.id).usd, -500);
      expect(projections.envelopeUsdBalance(envelope.id), -500);

      // Reopening presents a fresh sheet: amount reset to zero.
      await tester.tap(find.byKey(const Key('openSheetButton')));
      await tester.pumpAndSettle();
      expect(find.text('0.00'), findsOneWidget);
    });

    testWidgets('saving a Bs expense posts a realization with a '
        'differential using the parallel rate', (tester) async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);
      final catalog = await container.read(catalogRepositoryProvider.future);
      final account = Account(
        id: AccountId('acc-ves'),
        name: 'Bs wallet',
        nativeCurrency: CurrencyCode('VES'),
        isArchived: false,
        updatedAt: DateTime.now(),
      );
      await catalog.saveAccount(account);
      final envelope = Envelope(
        id: EnvelopeId('env-food'),
        name: 'Food',
        role: EnvelopeRole.none,
        isArchived: false,
        updatedAt: DateTime.now(),
      );
      await catalog.saveEnvelope(envelope);

      // Fund the account so there's balance to spend from.
      final rateSeries = await container.read(rateSeriesProvider.future);
      await rateSeries.append(
        RateObservation(
          currency: CurrencyCode('VES'),
          nativePerUsd: Decimal.parse('20.00'),
          observedAt: DateTime.now().toUtc(),
          source: 'manual:paralelo',
        ),
      );
      final projections = container.read(ledgerProjectionsProvider);
      // Directly seed a balance via the opening system envelope through the
      // existing projections API isn't available here, so give the account
      // plenty of native balance through a first small realization-less
      // path: append an opening event via the store directly.
      final store = await container.read(eventStoreProvider.future);
      await store.append(
        Transaction.create(
          metadata: TransactionMetadata(
            eventId: EventId('evt-opening'),
            type: 'Opening',
            occurredAt: DomainTimestamp(DateTime.now().toUtc()),
            recordedAt: DomainTimestamp(DateTime.now().toUtc()),
            deviceId: 'dev',
            schemaVersion: 1,
          ),
          postings: [
            Posting(
              target: AccountTarget(account.id),
              amountNative: Money(
                amount: BigInt.from(100000),
                currency: CurrencyCode('VES'),
              ),
              currency: CurrencyCode('VES'),
              amountUsd: 5000,
            ),
            Posting(
              target: EnvelopeTarget(
                catalog.getSystemEnvelope(EnvelopeRole.opening),
              ),
              amountNative: Money(
                amount: BigInt.from(5000),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: 5000,
            ),
          ],
        ),
      );
      projections.apply((await store.get(EventId('evt-opening')))!);

      await _openSheet(tester, existing: container);

      await tester.tap(find.byKey(const Key('keypadDigit_5')));
      await tester.tap(find.byKey(const Key('keypadDigit_0')));
      await tester.tap(find.byKey(const Key('keypadDigit_0')));
      await tester.tap(find.byKey(const Key('keypadDigit_0')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('quickAddSaveButton')));
      await tester.tap(find.byKey(const Key('quickAddSaveButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('numericKeypad')), findsNothing);

      final log = await store.queryLog();
      final tx = log.last;
      expect(tx.metadata.type, 'ForeignCurrencyExpense');
      expect(tx.postings.length, 3);
    });

    testWidgets('a Bs Gasto blocks Save and offers a shortcut to register '
        'the rate when none exists yet, instead of surfacing the raw '
        'exception after a failed save (#112/#119, ADR-0018 §7)', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);
      final catalog = await container.read(catalogRepositoryProvider.future);
      final account = Account(
        id: AccountId('acc-ves'),
        name: 'Bs wallet',
        nativeCurrency: CurrencyCode('VES'),
        isArchived: false,
        updatedAt: DateTime.now(),
      );
      await catalog.saveAccount(account);
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

      await tester.tap(find.byKey(const Key('keypadDigit_5')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('rateUnavailableMessage')), findsOneWidget);
      final saveButton = tester.widget<ElevatedButton>(
        find.byKey(const Key('quickAddSaveButton')),
      );
      expect(saveButton.onPressed, isNull);

      expect(find.textContaining('RateNotAvailable'), findsNothing);
      expect(find.textContaining('UsdOnlyOperation'), findsNothing);

      await tester.ensureVisible(find.byKey(const Key('registerRateShortcut')));
      await tester.tap(find.byKey(const Key('registerRateShortcut')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('paraleloRateField')), findsOneWidget);
    });

    testWidgets('an Ingreso to a Bs account blocks Save and offers a '
        'shortcut to register the rate when none exists yet (#119, '
        'ADR-0018 §7)', (tester) async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);
      final catalog = await container.read(catalogRepositoryProvider.future);
      final account = Account(
        id: AccountId('acc-ves'),
        name: 'Bs wallet',
        nativeCurrency: CurrencyCode('VES'),
        isArchived: false,
        updatedAt: DateTime.now(),
      );
      await catalog.saveAccount(account);

      await _openSheet(tester, existing: container);

      await tester.tap(find.byKey(const Key('captureModeIngreso')));
      await tester.pumpAndSettle();
      await pickCatalogItem(tester, 'incomeAccountChip_acc-ves');
      await tester.tap(find.byKey(const Key('keypadDigit_5')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('rateUnavailableMessage')), findsOneWidget);
      final saveButton = tester.widget<ElevatedButton>(
        find.byKey(const Key('quickAddSaveButton')),
      );
      expect(saveButton.onPressed, isNull);

      expect(find.textContaining('RateNotAvailable'), findsNothing);
    });

    testWidgets('a Bs Gasto shows the valuation rate and date once one is '
        "registered — today's rate never blocks Save (ADR-0018 §6)", (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);
      final catalog = await container.read(catalogRepositoryProvider.future);
      final account = Account(
        id: AccountId('acc-ves'),
        name: 'Bs wallet',
        nativeCurrency: CurrencyCode('VES'),
        isArchived: false,
        updatedAt: DateTime.now(),
      );
      await catalog.saveAccount(account);
      await catalog.saveEnvelope(
        Envelope(
          id: EnvelopeId('env-food'),
          name: 'Food',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );
      final rateSeries = await container.read(rateSeriesProvider.future);
      await rateSeries.append(
        RateObservation(
          currency: CurrencyCode('VES'),
          nativePerUsd: Decimal.parse('400.00'),
          observedAt: DateTime.now().toUtc(),
          source: 'manual:paralelo',
        ),
      );

      await _openSheet(tester, existing: container);

      await tester.tap(find.byKey(const Key('keypadDigit_5')));
      await tester.pumpAndSettle();

      expect(
        find.text('Valorado a 400.00 VES/USD · manual, hoy'),
        findsOneWidget,
      );
      final saveButton = tester.widget<ElevatedButton>(
        find.byKey(const Key('quickAddSaveButton')),
      );
      expect(saveButton.onPressed, isNotNull);
    });

    testWidgets('a Bs Gasto warns when the latest rate is stale but still '
        'lets the user save (ADR-0018 §6)', (tester) async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);
      final catalog = await container.read(catalogRepositoryProvider.future);
      final account = Account(
        id: AccountId('acc-ves'),
        name: 'Bs wallet',
        nativeCurrency: CurrencyCode('VES'),
        isArchived: false,
        updatedAt: DateTime.now(),
      );
      await catalog.saveAccount(account);
      await catalog.saveEnvelope(
        Envelope(
          id: EnvelopeId('env-food'),
          name: 'Food',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );
      final rateSeries = await container.read(rateSeriesProvider.future);
      await rateSeries.append(
        RateObservation(
          currency: CurrencyCode('VES'),
          nativePerUsd: Decimal.parse('400.00'),
          observedAt: DateTime.now().toUtc().subtract(const Duration(days: 2)),
          source: 'manual:paralelo',
        ),
      );

      await _openSheet(tester, existing: container);

      await tester.tap(find.byKey(const Key('keypadDigit_5')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('staleRateWarning')), findsOneWidget);
      expect(find.byKey(const Key('registerRateShortcut')), findsOneWidget);
      final saveButton = tester.widget<ElevatedButton>(
        find.byKey(const Key('quickAddSaveButton')),
      );
      expect(saveButton.onPressed, isNotNull);
    });

    testWidgets(
      'a Bs Gasto valued by an automatic source names it and shows its '
      'recency, not just the number (#165, ADR-0018 "la app siempre '
      'anuncia con qué valoró")',
      (tester) async {
        final container = ProviderContainer(
          overrides: [isWebProvider.overrideWithValue(true)],
        );
        addTearDown(container.dispose);
        final catalog = await container.read(catalogRepositoryProvider.future);
        final account = Account(
          id: AccountId('acc-ves'),
          name: 'Bs wallet',
          nativeCurrency: CurrencyCode('VES'),
          isArchived: false,
          updatedAt: DateTime.now(),
        );
        await catalog.saveAccount(account);
        await catalog.saveEnvelope(
          Envelope(
            id: EnvelopeId('env-food'),
            name: 'Food',
            role: EnvelopeRole.none,
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );
        // Stay within the current calendar day regardless of what time the
        // suite happens to run at (e.g. shortly after local midnight, where
        // a flat 2h lookback would roll into "yesterday" and hit the stale
        // branch instead of the today/recency one under test).
        final hoursAgo = DateTime.now().hour >= 2 ? 2 : 0;
        final rateSeries = await container.read(rateSeriesProvider.future);
        await rateSeries.append(
          RateObservation(
            currency: CurrencyCode('VES'),
            nativePerUsd: Decimal.parse('845.88'),
            observedAt: DateTime.now().toUtc().subtract(
              Duration(hours: hoursAgo),
            ),
            source: 'binancep2p:ask',
          ),
        );

        await _openSheet(tester, existing: container);

        await tester.tap(find.byKey(const Key('keypadDigit_5')));
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Valorado a 845.88 VES/USD · Binance P2P, hace $hoursAgo h',
          ),
          findsOneWidget,
        );
        final saveButton = tester.widget<ElevatedButton>(
          find.byKey(const Key('quickAddSaveButton')),
        );
        expect(saveButton.onPressed, isNotNull);
      },
    );

    testWidgets('recording a manual paralela from Patrimonio and returning to '
        'capture updates the announcement and the posted value (#165)', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);
      final catalog = await container.read(catalogRepositoryProvider.future);
      final account = Account(
        id: AccountId('acc-ves'),
        name: 'Bs wallet',
        nativeCurrency: CurrencyCode('VES'),
        isArchived: false,
        updatedAt: DateTime.now(),
      );
      await catalog.saveAccount(account);
      final envelope = Envelope(
        id: EnvelopeId('env-food'),
        name: 'Food',
        role: EnvelopeRole.none,
        isArchived: false,
        updatedAt: DateTime.now(),
      );
      await catalog.saveEnvelope(envelope);

      // Record a manual paralela of 900 from the Patrimonio screen.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: PatrimonioScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('patrimonioOverflowMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('recordRatesAction')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('bcvRateField')), '40');
      await tester.enterText(find.byKey(const Key('paraleloRateField')), '900');
      await tester.tap(find.byKey(const Key('saveRatesButton')));
      await tester.pumpAndSettle();

      // Back to capture — same container, fresh sheet.
      await _openSheet(tester, existing: container);

      for (final digit in const ['1', '0', '0', '0', '0', '0', '0']) {
        await tester.tap(find.byKey(Key('keypadDigit_$digit')));
      }
      await tester.pumpAndSettle();

      expect(
        find.text('Valorado a 900.00 VES/USD · manual, hoy'),
        findsOneWidget,
      );

      await tester.ensureVisible(find.byKey(const Key('quickAddSaveButton')));
      await tester.tap(find.byKey(const Key('quickAddSaveButton')));
      await tester.pumpAndSettle();

      final store = await container.read(eventStoreProvider.future);
      final log = await store.queryLog();
      final tx = log.last;
      final expensePosting = tx.postings.firstWhere(
        (p) => p.target == EnvelopeTarget(envelope.id),
      );
      // 10,000.00 VES / 900 VES per USD = $11.11 (1111 cents), per the
      // PRD's numeric example for the Patrimonio → capture round trip.
      expect(expensePosting.amountUsd, -1111);
    });

    testWidgets('an Ingreso to a Bs account shows the valuation rate and '
        "date once one is registered — today's rate never blocks Save "
        '(ADR-0018 §6)', (tester) async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);
      final catalog = await container.read(catalogRepositoryProvider.future);
      final account = Account(
        id: AccountId('acc-ves'),
        name: 'Bs wallet',
        nativeCurrency: CurrencyCode('VES'),
        isArchived: false,
        updatedAt: DateTime.now(),
      );
      await catalog.saveAccount(account);
      final rateSeries = await container.read(rateSeriesProvider.future);
      await rateSeries.append(
        RateObservation(
          currency: CurrencyCode('VES'),
          nativePerUsd: Decimal.parse('400.00'),
          observedAt: DateTime.now().toUtc(),
          source: 'manual:paralelo',
        ),
      );

      await _openSheet(tester, existing: container);

      await tester.tap(find.byKey(const Key('captureModeIngreso')));
      await tester.pumpAndSettle();
      await pickCatalogItem(tester, 'incomeAccountChip_acc-ves');
      await tester.tap(find.byKey(const Key('keypadDigit_5')));
      await tester.pumpAndSettle();

      expect(
        find.text('Valorado a 400.00 VES/USD · manual, hoy'),
        findsOneWidget,
      );
      final saveButton = tester.widget<ElevatedButton>(
        find.byKey(const Key('quickAddSaveButton')),
      );
      expect(saveButton.onPressed, isNotNull);
    });

    testWidgets('an Ingreso to a Bs account warns when the latest rate is '
        'stale but still lets the user save (ADR-0018 §6)', (tester) async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);
      final catalog = await container.read(catalogRepositoryProvider.future);
      final account = Account(
        id: AccountId('acc-ves'),
        name: 'Bs wallet',
        nativeCurrency: CurrencyCode('VES'),
        isArchived: false,
        updatedAt: DateTime.now(),
      );
      await catalog.saveAccount(account);
      final rateSeries = await container.read(rateSeriesProvider.future);
      await rateSeries.append(
        RateObservation(
          currency: CurrencyCode('VES'),
          nativePerUsd: Decimal.parse('400.00'),
          observedAt: DateTime.now().toUtc().subtract(const Duration(days: 2)),
          source: 'manual:paralelo',
        ),
      );

      await _openSheet(tester, existing: container);

      await tester.tap(find.byKey(const Key('captureModeIngreso')));
      await tester.pumpAndSettle();
      await pickCatalogItem(tester, 'incomeAccountChip_acc-ves');
      await tester.tap(find.byKey(const Key('keypadDigit_5')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('staleRateWarning')), findsOneWidget);
      expect(find.byKey(const Key('registerRateShortcut')), findsOneWidget);
      final saveButton = tester.widget<ElevatedButton>(
        find.byKey(const Key('quickAddSaveButton')),
      );
      expect(saveButton.onPressed, isNotNull);
    });

    testWidgets('a Bs expense exceeding the account balance is recorded, '
        'not rejected, and leaves a negative balance (#113)', (tester) async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);
      final catalog = await container.read(catalogRepositoryProvider.future);
      final account = Account(
        id: AccountId('acc-ves'),
        name: 'Bs wallet',
        nativeCurrency: CurrencyCode('VES'),
        isArchived: false,
        updatedAt: DateTime.now(),
      );
      await catalog.saveAccount(account);
      await catalog.saveEnvelope(
        Envelope(
          id: EnvelopeId('env-food'),
          name: 'Food',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );
      final rateSeries = await container.read(rateSeriesProvider.future);
      await rateSeries.append(
        RateObservation(
          currency: CurrencyCode('VES'),
          nativePerUsd: Decimal.parse('20.00'),
          observedAt: DateTime.now().toUtc(),
          source: 'manual:paralelo',
        ),
      );

      await _openSheet(tester, existing: container);

      // No opening balance was funded, so any positive amount overdraws it —
      // it should post anyway (ADR-0017), not be rejected.
      await tester.tap(find.byKey(const Key('keypadDigit_5')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('quickAddSaveButton')));
      await tester.tap(find.byKey(const Key('quickAddSaveButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('numericKeypad')), findsNothing);

      final projections = container.read(ledgerProjectionsProvider);
      expect(
        projections.accountBalance(account.id).native.amount < BigInt.zero,
        isTrue,
      );

      final store = await container.read(eventStoreProvider.future);
      final log = await store.queryLog();
      final tx = log.last;
      expect(tx.metadata.type, 'ForeignCurrencyExpense');
      expect(tx.postings.length, 3);

      // The whole disposed amount is excess (no known balance to cover it),
      // valued at execution rate ⇒ zero differential.
      final differentialId = catalog.getSystemEnvelope(
        EnvelopeRole.differential,
      );
      final differentialPosting = tx.postings.firstWhere(
        (p) => p.target == EnvelopeTarget(differentialId),
      );
      expect(differentialPosting.amountUsd, 0);
    });
  });

  group('account creation feeds the capture cartel (#174)', () {
    testWidgets('accepting the suggested rate at account creation values a Bs '
        'expense from Binance P2P, not manual', (tester) async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);
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
      final hoursAgo = DateTime.now().hour >= 2 ? 2 : 0;
      final rateSeries = await container.read(rateSeriesProvider.future);
      await rateSeries.append(
        RateObservation(
          currency: CurrencyCode('VES'),
          nativePerUsd: Decimal.parse('846.50'),
          observedAt: DateTime.now().toUtc().subtract(
            Duration(hours: hoursAgo),
          ),
          source: 'binancep2p:ask',
        ),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AccountsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('addAccountFab')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('accountNameField')), 'BdV');
      await tester.tap(find.byKey(const Key('accountCurrencyDropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('VES').last);
      await tester.pumpAndSettle();
      // The suggested rate is left as-is — the user never types a rate.
      await tester.tap(find.byKey(const Key('saveAccountButton')));
      await tester.pumpAndSettle();

      await _openSheet(tester, existing: container);

      for (final digit in const ['1', '0', '0', '0', '0']) {
        await tester.tap(find.byKey(Key('keypadDigit_$digit')));
      }
      await tester.pumpAndSettle();

      expect(
        find.text('Valorado a 846.50 VES/USD · Binance P2P, hace $hoursAgo h'),
        findsOneWidget,
        reason:
            'accepting the suggestion must not have fabricated a manual '
            'observation that outranks the automatic one (#174)',
      );
    });

    testWidgets('overriding the suggested rate at account creation values a Bs '
        'expense from the manual observation', (tester) async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);
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
      final rateSeries = await container.read(rateSeriesProvider.future);
      await rateSeries.append(
        RateObservation(
          currency: CurrencyCode('VES'),
          nativePerUsd: Decimal.parse('846.50'),
          observedAt: DateTime.now().toUtc(),
          source: 'binancep2p:ask',
        ),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AccountsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('addAccountFab')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('accountNameField')), 'BdV');
      await tester.tap(find.byKey(const Key('accountCurrencyDropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('VES').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('openingBalanceRateField')),
        '900',
      );
      await tester.tap(find.byKey(const Key('saveAccountButton')));
      await tester.pumpAndSettle();

      await _openSheet(tester, existing: container);

      for (final digit in const ['1', '0', '0', '0', '0']) {
        await tester.tap(find.byKey(Key('keypadDigit_$digit')));
      }
      await tester.pumpAndSettle();

      expect(
        find.text('Valorado a 900.00 VES/USD · manual, hoy'),
        findsOneWidget,
      );
    });
  });

  group('U2 visual language (#281)', () {
    testWidgets('Save button names what it saves, per mode', (tester) async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);
      final catalog = await container.read(catalogRepositoryProvider.future);
      await catalog.saveAccount(
        Account(
          id: AccountId('acc-usd'),
          name: 'USD wallet',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      await _openSheet(tester, existing: container);

      expect(find.text('Guardar gasto'), findsOneWidget);

      await tester.tap(find.byKey(const Key('captureModeIngreso')));
      await tester.pump();
      expect(find.text('Guardar ingreso'), findsOneWidget);

      await tester.tap(find.byKey(const Key('captureModeMover')));
      await tester.pump();
      expect(find.text('Guardar movimiento'), findsOneWidget);
    });

    testWidgets(
      'each question group renders inside a card with an uppercase header',
      (tester) async {
        final container = ProviderContainer(
          overrides: [isWebProvider.overrideWithValue(true)],
        );
        addTearDown(container.dispose);
        final catalog = await container.read(catalogRepositoryProvider.future);
        await catalog.saveAccount(
          Account(
            id: AccountId('acc-usd'),
            name: 'USD wallet',
            nativeCurrency: CurrencyCode('USD'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );
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

        expect(find.text('¿DE QUÉ CUENTA?'), findsOneWidget);
        expect(find.text('¿DE QUÉ SOBRE SALE?'), findsOneWidget);
      },
    );

    testWidgets(
      'a selected chip fills with the tonal secondaryContainer color; an '
      'unselected chip stays outlined',
      (tester) async {
        final container = ProviderContainer(
          overrides: [isWebProvider.overrideWithValue(true)],
        );
        addTearDown(container.dispose);
        final catalog = await container.read(catalogRepositoryProvider.future);
        await catalog.saveAccount(
          Account(
            id: AccountId('acc-usd'),
            name: 'USD wallet',
            nativeCurrency: CurrencyCode('USD'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );
        await catalog.saveAccount(
          Account(
            id: AccountId('acc-usd-2'),
            name: 'Other wallet',
            nativeCurrency: CurrencyCode('USD'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        // Preselect "USD wallet" explicitly (#316: tapping a chip inside
        // the picker sheet now closes it immediately, so there's no way to
        // tap-then-inspect within the same open sheet as before).
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(
                body: QuickAddExpenseSheet(
                  preselectedGastoAccountId: AccountId('acc-usd'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('accountField')));
        await tester.pumpAndSettle();

        final selectedChip = tester.widget<ChoiceChip>(
          find.byKey(const Key('accountChip_acc-usd')),
        );
        final unselectedChip = tester.widget<ChoiceChip>(
          find.byKey(const Key('accountChip_acc-usd-2')),
        );

        final context = tester.element(
          find.byKey(const Key('accountChip_acc-usd')),
        );
        final colorScheme = Theme.of(context).colorScheme;

        expect(selectedChip.selectedColor, colorScheme.secondaryContainer);
        expect(selectedChip.side!.color, Colors.transparent);
        expect(unselectedChip.side!.color, colorScheme.outlineVariant);
      },
    );
  });

  group('catalog pickers open a searchable sheet instead of a chip row '
      '(#316, follows #313)', () {
    Future<void> saveAccounts(dynamic catalog, int count) async {
      for (var i = 0; i < count; i++) {
        await catalog.saveAccount(
          Account(
            id: AccountId('acc-$i'),
            name: 'Cuenta $i',
            nativeCurrency: CurrencyCode('USD'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );
      }
    }

    Future<void> saveEnvelopes(dynamic catalog, int count) async {
      for (var i = 0; i < count; i++) {
        await catalog.saveEnvelope(
          Envelope(
            id: EnvelopeId('env-$i'),
            name: 'Sobre $i',
            role: EnvelopeRole.none,
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );
      }
    }

    testWidgets(
      'with 23 accounts and 40 envelopes, the amount hero sits at the same '
      'dy as with 2 accounts/2 envelopes, and stays within 24px of the '
      "keypad's first row",
      (tester) async {
        Future<double> heroDyWith(
          WidgetTester tester,
          int accountCount,
          int envelopeCount,
        ) async {
          final container = ProviderContainer(
            overrides: [isWebProvider.overrideWithValue(true)],
          );
          addTearDown(container.dispose);
          final catalog = await container.read(
            catalogRepositoryProvider.future,
          );
          await saveAccounts(catalog, accountCount);
          await saveEnvelopes(catalog, envelopeCount);

          await _openSheet(tester, existing: container);
          return tester.getTopLeft(find.byKey(const Key('amountHero'))).dy;
        }

        final heroDySmall = await heroDyWith(tester, 2, 2);
        // Tear down the first sheet's tree (including its still-open modal
        // route) before mounting a second one in the same test.
        await tester.pumpWidget(const SizedBox.shrink());
        final heroDyLarge = await heroDyWith(tester, 23, 40);

        expect(heroDyLarge, heroDySmall);

        final heroBottom =
            tester.getBottomLeft(find.byKey(const Key('amountHero'))).dy;
        final keypadTop =
            tester.getTopLeft(find.byKey(const Key('numericKeypad'))).dy;
        expect(keypadTop - heroBottom, lessThanOrEqualTo(24));
      },
    );

    testWidgets(
      'with 23 accounts and 40 envelopes, the hero, the full keypad and '
      'Save are all visible in a 360x640 viewport without scrolling',
      (tester) async {
        final container = ProviderContainer(
          overrides: [isWebProvider.overrideWithValue(true)],
        );
        addTearDown(container.dispose);
        final catalog = await container.read(catalogRepositoryProvider.future);
        await saveAccounts(catalog, 23);
        await saveEnvelopes(catalog, 40);

        await _openSheet(
          tester,
          existing: container,
          surfaceSize: const Size(360, 640),
        );

        for (final key in const [
          'amountHero',
          'numericKeypad',
          'keypadDigit_9',
          'quickAddSaveButton',
        ]) {
          expect(
            tester.getRect(find.byKey(Key(key))).bottom,
            lessThanOrEqualTo(640),
            reason: '$key must be visible without scrolling',
          );
        }
      },
    );

    testWidgets(
      'tapping the account field opens a search sheet: Frecuentes above '
      'Todas, "bin" filters to matching accounts, tapping one selects it',
      (tester) async {
        final container = ProviderContainer(
          overrides: [isWebProvider.overrideWithValue(true)],
        );
        addTearDown(container.dispose);
        final catalog = await container.read(catalogRepositoryProvider.future);
        await catalog.saveAccount(
          Account(
            id: AccountId('acc-efectivo'),
            name: 'Efectivo',
            nativeCurrency: CurrencyCode('USD'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );
        await catalog.saveAccount(
          Account(
            id: AccountId('acc-binance'),
            name: 'Binance',
            nativeCurrency: CurrencyCode('USD'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );
        final envelope = Envelope(
          id: EnvelopeId('env-comida'),
          name: 'Comida',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        );
        await catalog.saveEnvelope(envelope);

        // A prior expense from Efectivo makes it the last-used Account
        // (and Comida the most-frequent Envelope) — both become
        // "Frecuentes" (#316).
        final useCase = await container.read(
          quickAddExpenseUseCaseProvider.future,
        );
        final deviceId = await container.read(deviceIdProvider.future);
        await useCase(
          eventId: EventId('evt-1'),
          deviceId: deviceId,
          accountId: AccountId('acc-efectivo'),
          envelopeId: envelope.id,
          amount: Money(
            amount: BigInt.from(100),
            currency: CurrencyCode('USD'),
          ),
          occurredAt: DomainTimestamp(DateTime.now().toUtc()),
        );

        await _openSheet(tester, existing: container);
        await tester.tap(find.byKey(const Key('accountField')));
        await tester.pumpAndSettle();

        expect(find.text('FRECUENTES'), findsOneWidget);
        expect(find.text('TODAS'), findsOneWidget);
        final frequentDy =
            tester
                .getCenter(find.byKey(const Key('accountChip_acc-efectivo')))
                .dy;
        final allDy =
            tester
                .getCenter(find.byKey(const Key('accountChip_acc-binance')))
                .dy;
        expect(frequentDy, lessThan(allDy));

        await tester.enterText(
          find.byKey(const Key('catalogPickerSearchField')),
          'bin',
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('accountChip_acc-binance')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('accountChip_acc-efectivo')), findsNothing);

        await tester.tap(find.byKey(const Key('accountChip_acc-binance')));
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byKey(const Key('accountField')),
            matching: find.text('Binance · USD'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'the Gasto envelope field behaves the same: Frecuentes above Todas, '
      'search filters by substring, tapping selects',
      (tester) async {
        final container = ProviderContainer(
          overrides: [isWebProvider.overrideWithValue(true)],
        );
        addTearDown(container.dispose);
        final catalog = await container.read(catalogRepositoryProvider.future);
        final account = Account(
          id: AccountId('acc-efectivo'),
          name: 'Efectivo',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        );
        await catalog.saveAccount(account);
        final comida = Envelope(
          id: EnvelopeId('env-comida'),
          name: 'Comida',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        );
        final inversion = Envelope(
          id: EnvelopeId('env-inversion'),
          name: 'Inversión',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        );
        await catalog.saveEnvelope(comida);
        await catalog.saveEnvelope(inversion);

        final useCase = await container.read(
          quickAddExpenseUseCaseProvider.future,
        );
        final deviceId = await container.read(deviceIdProvider.future);
        await useCase(
          eventId: EventId('evt-1'),
          deviceId: deviceId,
          accountId: account.id,
          envelopeId: comida.id,
          amount: Money(
            amount: BigInt.from(100),
            currency: CurrencyCode('USD'),
          ),
          occurredAt: DomainTimestamp(DateTime.now().toUtc()),
        );

        await _openSheet(tester, existing: container);
        await tester.tap(find.byKey(const Key('envelopeField')));
        await tester.pumpAndSettle();

        expect(find.text('FRECUENTES'), findsOneWidget);
        expect(find.text('TODAS'), findsOneWidget);
        final frequentDy =
            tester
                .getCenter(find.byKey(const Key('envelopeChip_env-comida')))
                .dy;
        final allDy =
            tester
                .getCenter(find.byKey(const Key('envelopeChip_env-inversion')))
                .dy;
        expect(frequentDy, lessThan(allDy));

        await tester.enterText(
          find.byKey(const Key('catalogPickerSearchField')),
          'inver',
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('envelopeChip_env-inversion')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('envelopeChip_env-comida')), findsNothing);

        await tester.tap(find.byKey(const Key('envelopeChip_env-inversion')));
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byKey(const Key('envelopeField')),
            matching: find.text('Inversión'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Mover Desde and Hacia behave the same: Frecuentes above Todas, '
      'search filters, tapping selects',
      (tester) async {
        final container = ProviderContainer(
          overrides: [isWebProvider.overrideWithValue(true)],
        );
        addTearDown(container.dispose);
        final catalog = await container.read(catalogRepositoryProvider.future);
        final zelle = Account(
          id: AccountId('acc-zelle'),
          name: 'Zelle',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        );
        final binance = Account(
          id: AccountId('acc-binance'),
          name: 'Binance',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        );
        final efectivo = Account(
          id: AccountId('acc-efectivo'),
          name: 'Efectivo',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        );
        await catalog.saveAccount(zelle);
        await catalog.saveAccount(binance);
        await catalog.saveAccount(efectivo);

        // A prior Mover from Zelle to Binance makes that pair "Frecuentes"
        // on both sides (#316).
        final moverUseCase = await container.read(
          quickAddMoverUseCaseProvider.future,
        );
        final deviceId = await container.read(deviceIdProvider.future);
        await moverUseCase(
          eventId: EventId('evt-mover-1'),
          deviceId: deviceId,
          sourceAccountId: zelle.id,
          destinationAccountId: binance.id,
          givenAmount: Money(
            amount: BigInt.from(100),
            currency: CurrencyCode('USD'),
          ),
          receivedAmount: null,
          rate: null,
          occurredAt: DomainTimestamp(DateTime.now().toUtc()),
        );

        await _openSheet(tester, existing: container);
        await tester.tap(find.byKey(const Key('captureModeMover')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('moverSourceField')));
        await tester.pumpAndSettle();

        expect(find.text('FRECUENTES'), findsOneWidget);
        expect(find.text('TODAS'), findsOneWidget);
        expect(
          tester
              .getCenter(find.byKey(const Key('moverSourceChip_acc-zelle')))
              .dy,
          lessThan(
            tester
                .getCenter(
                  find.byKey(const Key('moverSourceChip_acc-efectivo')),
                )
                .dy,
          ),
        );

        await tester.enterText(
          find.byKey(const Key('catalogPickerSearchField')),
          'efect',
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('moverSourceChip_acc-efectivo')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('moverSourceChip_acc-zelle')),
          findsNothing,
        );
        await tester.tap(find.byKey(const Key('moverSourceChip_acc-efectivo')));
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byKey(const Key('moverSourceField')),
            matching: find.text('Efectivo · USD'),
          ),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('moverDestinationField')));
        await tester.pumpAndSettle();

        expect(find.text('FRECUENTES'), findsOneWidget);
        expect(find.text('TODAS'), findsOneWidget);
        expect(
          tester
              .getCenter(
                find.byKey(const Key('moverDestinationChip_acc-binance')),
              )
              .dy,
          lessThan(
            tester
                .getCenter(
                  find.byKey(const Key('moverDestinationChip_acc-zelle')),
                )
                .dy,
          ),
        );

        await tester.enterText(
          find.byKey(const Key('catalogPickerSearchField')),
          'zell',
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('moverDestinationChip_acc-zelle')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('moverDestinationChip_acc-binance')),
          findsNothing,
        );
        await tester.tap(
          find.byKey(const Key('moverDestinationChip_acc-zelle')),
        );
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byKey(const Key('moverDestinationField')),
            matching: find.text('Zelle · USD'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'both Distribution sobre fields behave the same: Frecuentes above '
      'Todas, search filters, tapping selects',
      (tester) async {
        final container = ProviderContainer(
          overrides: [isWebProvider.overrideWithValue(true)],
        );
        addTearDown(container.dispose);
        final catalog = await container.read(catalogRepositoryProvider.future);
        final account = Account(
          id: AccountId('acc-efectivo'),
          name: 'Efectivo',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        );
        await catalog.saveAccount(account);
        final comida = Envelope(
          id: EnvelopeId('env-comida'),
          name: 'Comida',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        );
        final ahorros = Envelope(
          id: EnvelopeId('env-ahorros'),
          name: 'Ahorros',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        );
        final mercado = Envelope(
          id: EnvelopeId('env-mercado'),
          name: 'Mercado',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        );
        await catalog.saveEnvelope(comida);
        await catalog.saveEnvelope(ahorros);
        await catalog.saveEnvelope(mercado);

        final useCase = await container.read(
          quickAddExpenseUseCaseProvider.future,
        );
        final deviceId = await container.read(deviceIdProvider.future);
        await useCase(
          eventId: EventId('evt-1'),
          deviceId: deviceId,
          accountId: account.id,
          envelopeId: comida.id,
          amount: Money(
            amount: BigInt.from(100),
            currency: CurrencyCode('USD'),
          ),
          occurredAt: DomainTimestamp(DateTime.now().toUtc()),
        );

        await _openSheet(tester, existing: container);
        await tester.tap(find.byKey(const Key('captureModeMover')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('moverModeEnvelopes')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('distributionSourceField')));
        await tester.pumpAndSettle();

        expect(find.text('FRECUENTES'), findsOneWidget);
        expect(find.text('TODAS'), findsOneWidget);
        expect(
          tester
              .getCenter(
                find.byKey(const Key('distributionSourceChip_env-comida')),
              )
              .dy,
          lessThan(
            tester
                .getCenter(
                  find.byKey(const Key('distributionSourceChip_env-mercado')),
                )
                .dy,
          ),
        );

        await tester.enterText(
          find.byKey(const Key('catalogPickerSearchField')),
          'merc',
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('distributionSourceChip_env-mercado')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('distributionSourceChip_env-comida')),
          findsNothing,
        );
        await tester.tap(
          find.byKey(const Key('distributionSourceChip_env-mercado')),
        );
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byKey(const Key('distributionSourceField')),
            matching: find.text('Mercado'),
          ),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('distributionDestinationField')));
        await tester.pumpAndSettle();

        expect(find.text('FRECUENTES'), findsOneWidget);
        expect(find.text('TODAS'), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('catalogPickerSearchField')),
          'ahor',
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('distributionDestinationChip_env-ahorros')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('distributionDestinationChip_env-comida')),
          findsNothing,
        );
        await tester.tap(
          find.byKey(const Key('distributionDestinationChip_env-ahorros')),
        );
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byKey(const Key('distributionDestinationField')),
            matching: find.text('Ahorros'),
          ),
          findsOneWidget,
        );
      },
    );
  });
}
