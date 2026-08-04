import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:cuentaria_app/main.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:cuentaria_app/ui/screens/movements/movement_detail_screen.dart';
import 'package:cuentaria_app/ui/screens/movements/movements_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';

Future<void> _tapDigits(WidgetTester tester, String digits) async {
  for (final digit in digits.split('')) {
    await tester.tap(find.byKey(Key('keypadDigit_$digit')));
  }
  await tester.pump();
}

Future<void> _createAccount(
  WidgetTester tester, {
  required String name,
  String currency = 'USD',
  String? openingBalance,
  String? openingBalanceRate,
}) async {
  await tester.tap(find.byKey(const Key('addAccountFab')));
  await tester.pumpAndSettle();

  await tester.enterText(find.byKey(const Key('accountNameField')), name);

  if (currency != 'USD') {
    await tester.tap(find.byKey(const Key('accountCurrencyDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(currency).last);
    await tester.pumpAndSettle();
  }

  if (openingBalance != null) {
    await tester.enterText(
      find.byKey(const Key('openingBalanceField')),
      openingBalance,
    );
    await tester.pumpAndSettle();
  }

  if (openingBalanceRate != null) {
    await tester.enterText(
      find.byKey(const Key('openingBalanceRateField')),
      openingBalanceRate,
    );
  }

  await tester.tap(find.byKey(const Key('saveAccountButton')));
  await tester.pumpAndSettle();
}

Future<void> _createEnvelope(
  WidgetTester tester, {
  required String name,
  required String fundingType,
  required String amount,
}) async {
  await tester.tap(find.byKey(const Key('createEnvelopeButton')));
  await tester.pumpAndSettle();

  await tester.enterText(find.byKey(const Key('nameField')), name);

  await tester.tap(find.byKey(const Key('targetKindDropdown')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(fundingType).last);
  await tester.pumpAndSettle();

  await tester.enterText(find.byKey(const Key('targetAmountField')), amount);

  await tester.tap(find.byKey(const Key('saveEnvelopeButton')));
  await tester.pumpAndSettle();
}

Future<void> _addCascadeStep(
  WidgetTester tester, {
  required String envelopeName,
  required String fundingType,
}) async {
  await tester.tap(find.byKey(const Key('addCascadeStepButton')));
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('stepEnvelopeDropdown')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(envelopeName).last);
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('stepFundingTypeDropdown')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(fundingType).last);
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('saveStepButton')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'a month in the life: cold boot through real bootstrap, providers, '
    'projections and UI — accounts, envelopes, cascade, distribution, '
    'income, mover, a foreign-currency expense and its reversal (#99)',
    (tester) async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const MyApp()),
      );
      await tester.pumpAndSettle();

      // -- Accounts: Bancamiga (USD, opening $200), Binance (USD, opening
      // $150), BdV (VES, no opening) -----------------------------------
      await tester.tap(find.byKey(const Key('manageAccountsAction')));
      await tester.pumpAndSettle();

      await _createAccount(tester, name: 'Bancamiga', openingBalance: '200');
      await _createAccount(tester, name: 'Binance', openingBalance: '150');
      // #112: a non-USD account always asks for a rate, even with no
      // opening balance — recorded as today's parallel rate, later
      // superseded by the explicit "record today's rates" step below.
      await _createAccount(
        tester,
        name: 'BdV',
        currency: 'VES',
        openingBalanceRate: '1',
      );

      await tester.pageBack();
      await tester.pumpAndSettle();

      final catalog = await container.read(catalogRepositoryProvider.future);
      final projections = container.read(ledgerProjectionsProvider);
      final bancamigaId =
          catalog.accounts.singleWhere((a) => a.name == 'Bancamiga').id;
      final binanceId =
          catalog.accounts.singleWhere((a) => a.name == 'Binance').id;
      final bdvId = catalog.accounts.singleWhere((a) => a.name == 'BdV').id;

      // #U1-15: Binance is a plain USD account, never a `USDT` currency.
      expect(
        catalog.accounts
            .singleWhere((a) => a.name == 'Binance')
            .nativeCurrency
            .value,
        'USD',
      );

      // -- Envelopes: Mercado (Cap $120), Mudanza (GoalLine $1000) ------
      await tester.tap(find.byKey(const Key('manageEnvelopesAction')));
      await tester.pumpAndSettle();

      await _createEnvelope(
        tester,
        name: 'Mercado',
        fundingType: 'Cap',
        amount: '120',
      );
      await _createEnvelope(
        tester,
        name: 'Mudanza',
        fundingType: 'Goal line',
        amount: '1000',
      );

      await tester.pageBack();
      await tester.pumpAndSettle();

      final mercadoId =
          catalog.envelopes.singleWhere((e) => e.name == 'Mercado').id;
      final mudanzaId =
          catalog.envelopes.singleWhere((e) => e.name == 'Mudanza').id;

      // -- Cascade (fill Mercado to its cap, catch-all into Mudanza),
      // configured from the Apertura notice — Stage itself is hidden while
      // its balance is zero (S2: Stage/Apertura only surface with a
      // positive balance) ------------------------------------------------
      await tester.tap(find.byKey(const Key('openingBalanceNotice')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('noCascadeMessage')), findsOneWidget);

      await tester.tap(find.byKey(const Key('editCascadeAction')));
      await tester.pumpAndSettle();

      await _addCascadeStep(
        tester,
        envelopeName: 'Mercado',
        fundingType: 'Fill to cap',
      );
      await _addCascadeStep(
        tester,
        envelopeName: 'Mudanza',
        fundingType: 'Catch-all',
      );

      await tester.tap(find.byKey(const Key('saveCascadeButton')));
      await tester.pumpAndSettle();

      // -- Distribute Apertura: $350 opening -> Mercado $120, Mudanza $230
      await tester.tap(find.byKey(const Key('applyDistributionButton')));
      await tester.pumpAndSettle();

      expect(projections.envelopeUsdBalance(mercadoId), 12000);
      expect(projections.envelopeUsdBalance(mudanzaId), 23000);

      // -- Income $500 "Cliente X" into Bancamiga -----------------------
      await tester.tap(find.byKey(const Key('quickAddExpenseFab')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('captureModeIngreso')));
      await tester.pump();

      await tester.tap(
        find.byKey(Key('incomeAccountChip_${bancamigaId.value}')),
      );
      await tester.enterText(
        find.byKey(const Key('incomeSourceField')),
        'Cliente X',
      );
      await _tapDigits(tester, '50000');

      await tester.ensureVisible(find.byKey(const Key('quickAddSaveButton')));
      await tester.tap(find.byKey(const Key('quickAddSaveButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('incomeDistributeCta')), findsOneWidget);

      await tester.tap(find.byKey(const Key('incomeDistributeCta')));
      await tester.pumpAndSettle();

      // -- Distribute Stage: $500 -> Mercado stays at cap, Mudanza +$500
      await tester.tap(find.byKey(const Key('applyDistributionButton')));
      await tester.pumpAndSettle();

      expect(projections.envelopeUsdBalance(mercadoId), 12000);
      expect(projections.envelopeUsdBalance(mudanzaId), 73000);

      // -- Record today's VES rates (needed before the Bs expense) ------
      await tester.tap(find.byKey(const Key('recordRatesAction')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('bcvRateField')), '50');
      await tester.enterText(find.byKey(const Key('paraleloRateField')), '40');
      await tester.tap(find.byKey(const Key('saveRatesButton')));
      await tester.pumpAndSettle();

      // -- Mover $100 Binance -> BdV, executed at 40 Bs/USD -------------
      await tester.tap(find.byKey(const Key('quickAddExpenseFab')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('captureModeMover')));
      await tester.pump();

      await tester.tap(find.byKey(Key('moverSourceChip_${binanceId.value}')));
      await tester.pump();
      await tester.tap(find.byKey(Key('moverDestinationChip_${bdvId.value}')));
      await tester.pump();

      await _tapDigits(tester, '10000'); // $100.00 given

      await tester.enterText(
        find.byKey(const Key('moverRateInputField')),
        '4000', // 4000.00 Bs received -> derives the 40.00 executed rate
      );
      await tester.pump();

      await tester.ensureVisible(find.byKey(const Key('quickAddSaveButton')));
      await tester.tap(find.byKey(const Key('quickAddSaveButton')));
      await tester.pumpAndSettle();

      expect(projections.accountBalance(binanceId).usd, 5000);
      expect(
        projections.accountBalance(bdvId).native.amount,
        BigInt.from(400000),
      );
      expect(projections.accountBalance(bdvId).usd, 10000);

      // -- A wrong Bs expense from BdV into Mercado, then reversed ------
      await tester.tap(find.byKey(const Key('quickAddExpenseFab')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(Key('accountChip_${bdvId.value}')));
      await tester.tap(find.byKey(Key('envelopeChip_${mercadoId.value}')));
      await _tapDigits(tester, '200000'); // 2000.00 Bs

      await tester.ensureVisible(find.byKey(const Key('quickAddSaveButton')));
      await tester.tap(find.byKey(const Key('quickAddSaveButton')));
      await tester.pumpAndSettle();

      expect(projections.accountBalance(bdvId).usd, 5000);
      expect(projections.envelopeUsdBalance(mercadoId), 7000);

      // -- Movements: the expense is listed; reverse it, then refuse a
      // second reversal (double-reversal guard) ------------------------
      await tester.tap(find.byIcon(Icons.list_alt_outlined));
      await tester.pumpAndSettle();

      final store = await container.read(eventStoreProvider.future);
      final log = await store.queryLog();
      expect(log, hasLength(7));
      final expenseEventId =
          log
              .singleWhere((t) => t.metadata.type == 'ForeignCurrencyExpense')
              .metadata
              .eventId;

      // -- Movements amounts (#99 bugfix): each row shows what actually
      // moved on the Account dimension, not a double count of the
      // Account+Envelope legs — in insertion (chronological) order:
      // Opening Bancamiga, Opening Binance, Distribution (Apertura),
      // Income, Distribution (Stage), AcquisitionConversion (Mover),
      // ForeignCurrencyExpense. The Mover is an inter-account move (no
      // Envelope leg), so its net is zero by the self-balancing invariant;
      // the row shows the moved amount instead of that $0.00. -----------
      expect(log[0].metadata.type, 'Opening');
      expect(log[1].metadata.type, 'Opening');
      expect(log[2].metadata.type, 'Distribution');
      expect(log[3].metadata.type, 'Income');
      expect(log[4].metadata.type, 'Distribution');
      expect(log[5].metadata.type, 'AcquisitionConversion');
      expect(log[6].metadata.type, 'ForeignCurrencyExpense');

      void expectRowAmount(EventId eventId, String amount) {
        expect(
          find.descendant(
            of: find.byKey(Key('movement_${eventId.value}')),
            matching: find.text(amount),
          ),
          findsOneWidget,
        );
      }

      expectRowAmount(log[0].metadata.eventId, '\$200.00'); // Bancamiga open
      expectRowAmount(log[1].metadata.eventId, '\$150.00'); // Binance open
      expectRowAmount(log[2].metadata.eventId, '\$0.00'); // Apertura split
      expectRowAmount(log[3].metadata.eventId, '\$500.00'); // Income
      expectRowAmount(log[4].metadata.eventId, '\$0.00'); // Stage split
      expectRowAmount(log[5].metadata.eventId, '\$100.00'); // Mover (moved amt)
      expectRowAmount(expenseEventId, '-\$50.00'); // BdV expense

      await tester.tap(find.byKey(Key('movement_${expenseEventId.value}')));
      await tester.pumpAndSettle();

      expect(find.byType(MovementDetailScreen), findsOneWidget);
      expect(find.textContaining('BdV'), findsOneWidget);
      expect(find.textContaining('Mercado'), findsOneWidget);
      expect(find.byKey(const Key('reverseButton')), findsOneWidget);

      await tester.tap(find.byKey(const Key('reverseButton')));
      await tester.pumpAndSettle();

      expect(find.byType(MovementsScreen), findsOneWidget);
      final logAfterReversal = await store.queryLog();
      expect(logAfterReversal, hasLength(8));

      await tester.tap(find.byKey(Key('movement_${expenseEventId.value}')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('alreadyReversedNotice')), findsOneWidget);
      expect(find.byKey(const Key('reverseButton')), findsNothing);

      await tester.pageBack();
      await tester.pumpAndSettle();

      // -- Patrimonio: the reversal restored every figure exactly -------
      await tester.tap(find.byIcon(Icons.pie_chart_outline));
      await tester.pumpAndSettle();

      expect(projections.envelopeUsdBalance(mercadoId), 12000);
      expect(projections.envelopeUsdBalance(mudanzaId), 73000);
      expect(projections.accountBalance(bdvId).usd, 10000);
      expect(
        projections.accountBalance(bdvId).native.amount,
        BigInt.from(400000),
      );

      expect(
        tester.widget<Text>(find.byKey(const Key('realCostAmount'))).data,
        '\$850.00',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('todayValueAmount'))).data,
        '\$850.00',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('unrealizedPnlAmount'))).data,
        'Unrealized P&L: \$0.00',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('bcvReferenceAmount'))).data,
        'BCV reference: \$830.00',
      );
      expect(find.byKey(const Key('missingRateFlag')), findsNothing);

      expect(
        find.descendant(
          of: find.byKey(const Key('accountGroup_USD')),
          matching: find.text('Real cost: \$750.00 · Today: \$750.00'),
        ),
        findsOneWidget,
      );

      // The VES group sits below the fold on the test surface — scroll the
      // Patrimonio list until it is actually built before asserting on it.
      await tester.dragUntilVisible(
        find.byKey(const Key('accountGroup_VES')),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('accountGroup_VES')),
          matching: find.text('Real cost: \$100.00 · Today: \$100.00'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'a client pays in Bs: Ingreso derives the foreign-currency valuation '
    'from the destination account (ADR-0018), crediting Stage with the '
    'USD equivalent while keeping the client source recorded and net '
    'worth in balance (#119)',
    (tester) async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const MyApp()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('manageAccountsAction')));
      await tester.pumpAndSettle();

      // A non-USD account always asks for a rate, even with no opening
      // balance (#112) — this doubles as BdV's first parallel Rate
      // Observation, consumed immediately by the Ingreso below.
      await _createAccount(
        tester,
        name: 'BdV',
        currency: 'VES',
        openingBalanceRate: '40',
      );

      await tester.pageBack();
      await tester.pumpAndSettle();

      final catalog = await container.read(catalogRepositoryProvider.future);
      final projections = container.read(ledgerProjectionsProvider);
      final bdvId = catalog.accounts.singleWhere((a) => a.name == 'BdV').id;
      final stageId = catalog.getSystemEnvelope(EnvelopeRole.stage);

      // -- A client pays 4000.00 Bs into BdV ----------------------------
      await tester.tap(find.byKey(const Key('quickAddExpenseFab')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('captureModeIngreso')));
      await tester.pump();

      await tester.tap(find.byKey(Key('incomeAccountChip_${bdvId.value}')));
      await tester.enterText(
        find.byKey(const Key('incomeSourceField')),
        'Cliente Bs',
      );
      await _tapDigits(tester, '400000'); // 4000.00 Bs

      await tester.ensureVisible(find.byKey(const Key('quickAddSaveButton')));
      await tester.tap(find.byKey(const Key('quickAddSaveButton')));
      await tester.pumpAndSettle();

      // -- Stage received the USD equivalent (4000.00 / 40 = $100.00),
      // the client source is recorded, and BdV shows the Bs it actually
      // received --------------------------------------------------------
      final store = await container.read(eventStoreProvider.future);
      final log = await store.queryLog();
      final incomeTx = log.singleWhere((t) => t.metadata.type == 'Income');
      expect(incomeTx.metadata.source, 'Cliente Bs');

      expect(projections.envelopeUsdBalance(stageId), 10000);
      expect(
        projections.accountBalance(bdvId).native.amount,
        BigInt.from(400000),
      );
      expect(projections.accountBalance(bdvId).usd, 10000);

      // Ingreso doesn't auto-close the sheet — it re-drains for another
      // capture (U1, #98) — so dismiss it before navigating elsewhere.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      // -- Net worth cuadra: BdV's real cost equals its today's value at
      // the same rate, with no unrealized P&L ---------------------------
      await tester.tap(find.byIcon(Icons.pie_chart_outline));
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('realCostAmount'))).data,
        '\$100.00',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('todayValueAmount'))).data,
        '\$100.00',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('unrealizedPnlAmount'))).data,
        'Unrealized P&L: \$0.00',
      );
    },
  );
}
