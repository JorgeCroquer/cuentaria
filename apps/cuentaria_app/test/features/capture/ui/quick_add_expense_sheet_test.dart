import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
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

Future<ProviderContainer> _openSheet(
  WidgetTester tester, {
  ProviderContainer? existing,
}) async {
  final container =
      existing ??
      ProviderContainer(overrides: [isWebProvider.overrideWithValue(true)]);
  addTearDown(container.dispose);

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

      final selectedAccountChip = tester.widget<ChoiceChip>(
        find.byKey(const Key('accountChip_acc-recent')),
      );
      expect(selectedAccountChip.selected, isTrue);

      final selectedEnvelopeChip = tester.widget<ChoiceChip>(
        find.byKey(const Key('envelopeChip_env-frequent')),
      );
      expect(selectedEnvelopeChip.selected, isTrue);

      // Frequency order: frequent (2x) before rare (1x).
      final frequentChipCenter = tester.getCenter(
        find.byKey(const Key('envelopeChip_env-frequent')),
      );
      final rareChipCenter = tester.getCenter(
        find.byKey(const Key('envelopeChip_env-rare')),
      );
      expect(frequentChipCenter.dx, lessThan(rareChipCenter.dx));
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

        expect(find.text('Bancamiga · USD'), findsOneWidget);
        expect(find.text('Bancamiga · VES'), findsOneWidget);
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

        await tester.tap(find.byKey(const Key('accountChip_acc-usd')));
        await tester.pump();
        expect(
          tester.widget<Text>(find.byKey(const Key('amountCurrency'))).data,
          'USD',
        );

        await tester.tap(find.byKey(const Key('accountChip_acc-ves')));
        await tester.pump();
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

      final today = DateTime.now();
      final expected =
          '${today.year.toString().padLeft(4, '0')}-'
          '${today.month.toString().padLeft(2, '0')}-'
          '${today.day.toString().padLeft(2, '0')}';
      expect(find.textContaining(expected), findsOneWidget);
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
      await tester.tap(find.byKey(const Key('incomeAccountChip_acc-ves')));
      await tester.pump();
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
      await tester.tap(find.byKey(const Key('incomeAccountChip_acc-ves')));
      await tester.pump();
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
      await tester.tap(find.byKey(const Key('incomeAccountChip_acc-ves')));
      await tester.pump();
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
}
