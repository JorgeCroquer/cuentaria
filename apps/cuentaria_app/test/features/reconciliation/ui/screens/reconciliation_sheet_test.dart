import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:cuentaria_app/features/reconciliation/ui/screens/reconciliation_sheet.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:cuentaria_app/providers/tasas_providers.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/domain/rate_observation.dart';

Future<ProviderContainer> _openSheet(
  WidgetTester tester,
  Account account, {
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
                  onPressed: () => showReconciliationSheet(context, account),
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

Future<void> _typeDigits(WidgetTester tester, String digits) async {
  for (final digit in digits.split('')) {
    await tester.tap(find.byKey(Key('keypadDigit_$digit')));
    await tester.pump();
  }
}

void main() {
  group('ReconciliationSheet', () {
    testWidgets('shows the projected balance before asking for the real one', (
      tester,
    ) async {
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

      await _openSheet(tester, account, existing: container);

      expect(find.byKey(const Key('projectedBalanceText')), findsOneWidget);
      expect(find.textContaining('0.00'), findsWidgets);
    });

    testWidgets('a zero real balance is declarable when the projected one '
        "isn't: shows the delta and absorbs on confirm (fix directive gap 1)", (
      tester,
    ) async {
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

      // Seed a projected balance of $0.50 via an opening posting.
      final store = await container.read(eventStoreProvider.future);
      final projections = container.read(ledgerProjectionsProvider);
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
                amount: BigInt.from(50),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: 50,
            ),
            Posting(
              target: EnvelopeTarget(
                catalog.getSystemEnvelope(EnvelopeRole.opening),
              ),
              amountNative: Money(
                amount: BigInt.from(50),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: 50,
            ),
          ],
        ),
      );
      projections.apply((await store.get(EventId('evt-opening')))!);

      await _openSheet(tester, account, existing: container);

      // Type "0" — a real digit, not "nothing typed".
      await _typeDigits(tester, '0');
      await tester.pump();

      expect(
        find.byKey(const Key('reconciliationAbsorbMessage')),
        findsOneWidget,
      );
      final confirmButton = tester.widget<ElevatedButton>(
        find.byKey(const Key('reconciliationConfirmButton')),
      );
      expect(confirmButton.onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('reconciliationConfirmButton')));
      await tester.pumpAndSettle();

      expect(projections.accountBalance(account.id).usd, 0);
      final adjustmentsId = catalog.getSystemEnvelope(EnvelopeRole.adjustments);
      expect(projections.envelopeUsdBalance(adjustmentsId), -50);
    });

    testWidgets('real balance equal to the projected one shows the '
        'nothing-to-reconcile message and posts nothing', (tester) async {
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

      await _openSheet(tester, account, existing: container);

      await _typeDigits(tester, '0');
      await tester.pump();

      expect(
        find.byKey(const Key('reconciliationNothingMessage')),
        findsOneWidget,
      );

      final store = await container.read(eventStoreProvider.future);
      expect(await store.queryLog(), isEmpty);
    });

    testWidgets('cancel posts nothing', (tester) async {
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

      await _openSheet(tester, account, existing: container);

      await _typeDigits(tester, '500');
      await tester.pump();
      await tester.tap(find.byKey(const Key('reconciliationCancelButton')));
      await tester.pumpAndSettle();

      final store = await container.read(eventStoreProvider.future);
      expect(await store.queryLog(), isEmpty);
    });

    testWidgets('a VES account with no observed rate blocks with a shortcut '
        'to register one (same behavior as quick capture, ADR-0018 §7)', (
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

      await _openSheet(tester, account, existing: container);

      expect(find.byKey(const Key('rateUnavailableMessage')), findsOneWidget);

      await tester.tap(find.byKey(const Key('registerRateShortcut')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('paraleloRateField')), findsOneWidget);
    });

    testWidgets('a VES account shortage absorbs once a rate is resolved, '
        'and the account/Adjustments balances square (fix directive gap 2)', (
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

      final rateSeries = await container.read(rateSeriesProvider.future);
      await rateSeries.append(
        RateObservation(
          currency: CurrencyCode('VES'),
          nativePerUsd: Decimal.parse('100.00'),
          observedAt: DateTime.now().toUtc(),
          source: 'manual:paralelo',
        ),
      );

      // Seed a projected balance of 100 VES minor units costing $1.00.
      final store = await container.read(eventStoreProvider.future);
      final projections = container.read(ledgerProjectionsProvider);
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
                amount: BigInt.from(100),
                currency: CurrencyCode('VES'),
              ),
              currency: CurrencyCode('VES'),
              amountUsd: 100,
            ),
            Posting(
              target: EnvelopeTarget(
                catalog.getSystemEnvelope(EnvelopeRole.opening),
              ),
              amountNative: Money(
                amount: BigInt.from(100),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: 100,
            ),
          ],
        ),
      );
      projections.apply((await store.get(EventId('evt-opening')))!);

      await _openSheet(tester, account, existing: container);

      // Real balance is 50 VES: delta = -50 minor units, under tolerance
      // once converted at 100 VES/USD (-$0.50).
      await _typeDigits(tester, '50');
      await tester.pump();

      expect(
        find.byKey(const Key('reconciliationAbsorbMessage')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('reconciliationConfirmButton')));
      await tester.pumpAndSettle();

      final adjustmentsId = catalog.getSystemEnvelope(EnvelopeRole.adjustments);
      expect(
        projections.accountBalance(account.id).native.amount,
        BigInt.from(50),
      );
      expect(projections.accountBalance(account.id).usd, 50);
      expect(projections.envelopeUsdBalance(adjustmentsId), -50);
    });

    testWidgets('a large surplus warns and only absorbs when the user '
        'confirms the escape hatch (ADR-0019 §1)', (tester) async {
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

      await _openSheet(tester, account, existing: container);

      await _typeDigits(tester, '500');
      await tester.pump();

      expect(
        find.byKey(const Key('reconciliationRouteWarning')),
        findsOneWidget,
      );
      final confirmButton = tester.widget<ElevatedButton>(
        find.byKey(const Key('reconciliationConfirmButton')),
      );
      expect(confirmButton.onPressed, isNull);

      await tester.ensureVisible(
        find.byKey(const Key('reconciliationAbsorbAnywayButton')),
      );
      await tester.tap(
        find.byKey(const Key('reconciliationAbsorbAnywayButton')),
      );
      await tester.pumpAndSettle();

      final projections = container.read(ledgerProjectionsProvider);
      expect(projections.accountBalance(account.id).usd, 500);
      final adjustmentsId = catalog.getSystemEnvelope(EnvelopeRole.adjustments);
      expect(projections.envelopeUsdBalance(adjustmentsId), 500);
    });

    testWidgets('a large surplus offers to register an Income with the '
        'amount pre-filled; confirming lands it in Stage, not Adjustments '
        '(ADR-0019 §2)', (tester) async {
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

      await _openSheet(tester, account, existing: container);

      await _typeDigits(tester, '500');
      await tester.pump();

      expect(
        find.byKey(const Key('reconciliationRouteWarning')),
        findsOneWidget,
      );

      final confirmIncomeButtonDisabled = tester.widget<ElevatedButton>(
        find.byKey(const Key('routeToIncomeConfirmButton')),
      );
      expect(confirmIncomeButtonDisabled.onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('routeToIncomeSourceField')),
        'Cobro olvidado',
      );
      await tester.pump();

      await tester.ensureVisible(
        find.byKey(const Key('routeToIncomeConfirmButton')),
      );
      await tester.tap(find.byKey(const Key('routeToIncomeConfirmButton')));
      await tester.pumpAndSettle();

      final store = await container.read(eventStoreProvider.future);
      final tx = (await store.queryLog()).single;
      expect(tx.metadata.type, 'Income');

      final projections = container.read(ledgerProjectionsProvider);
      expect(projections.accountBalance(account.id).usd, 500);
      final stageId = catalog.getSystemEnvelope(EnvelopeRole.stage);
      expect(projections.envelopeUsdBalance(stageId), 500);
      final adjustmentsId = catalog.getSystemEnvelope(EnvelopeRole.adjustments);
      expect(projections.envelopeUsdBalance(adjustmentsId), 0);
    });

    testWidgets('a large shortage offers to register an Expense with '
        'envelope selection; confirming discounts the chosen envelope', (
      tester,
    ) async {
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
      await catalog.saveEnvelope(
        Envelope(
          id: EnvelopeId('env-food'),
          name: 'Food',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      // Seed a projected balance of $10.00 via an opening posting.
      final store = await container.read(eventStoreProvider.future);
      final projections = container.read(ledgerProjectionsProvider);
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
                amount: BigInt.from(1000),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: 1000,
            ),
            Posting(
              target: EnvelopeTarget(
                catalog.getSystemEnvelope(EnvelopeRole.opening),
              ),
              amountNative: Money(
                amount: BigInt.from(1000),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: 1000,
            ),
          ],
        ),
      );
      projections.apply((await store.get(EventId('evt-opening')))!);

      await _openSheet(tester, account, existing: container);

      // Real balance is $2.00: delta = 200 - 1000 = -800, well past
      // tolerance ($1.00).
      await _typeDigits(tester, '200');
      await tester.pump();

      expect(
        find.byKey(const Key('reconciliationRouteWarning')),
        findsOneWidget,
      );

      final confirmExpenseButtonDisabled = tester.widget<ElevatedButton>(
        find.byKey(const Key('routeToExpenseConfirmButton')),
      );
      expect(confirmExpenseButtonDisabled.onPressed, isNull);

      await tester.ensureVisible(
        find.byKey(const Key('routeToExpenseEnvelopeChip_env-food')),
      );
      await tester.tap(
        find.byKey(const Key('routeToExpenseEnvelopeChip_env-food')),
      );
      await tester.pump();

      await tester.ensureVisible(
        find.byKey(const Key('routeToExpenseConfirmButton')),
      );
      await tester.tap(find.byKey(const Key('routeToExpenseConfirmButton')));
      await tester.pumpAndSettle();

      final tx = (await store.queryLog()).last;
      expect(tx.metadata.type, 'Expense');

      expect(projections.accountBalance(account.id).usd, 200);
      expect(projections.envelopeUsdBalance(EnvelopeId('env-food')), -800);
      final adjustmentsId = catalog.getSystemEnvelope(EnvelopeRole.adjustments);
      expect(projections.envelopeUsdBalance(adjustmentsId), 0);
    });

    testWidgets('an overdrawn account is squared by a routed Income and the '
        'negative balance is gone (ADR-0017 closure)', (tester) async {
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

      // Seed a projected balance of -$5.00 via an opening posting.
      final store = await container.read(eventStoreProvider.future);
      final projections = container.read(ledgerProjectionsProvider);
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
                amount: BigInt.from(-500),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: -500,
            ),
            Posting(
              target: EnvelopeTarget(
                catalog.getSystemEnvelope(EnvelopeRole.opening),
              ),
              amountNative: Money(
                amount: BigInt.from(-500),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: -500,
            ),
          ],
        ),
      );
      projections.apply((await store.get(EventId('evt-opening')))!);

      expect(projections.accountBalance(account.id).usd, -500);

      await _openSheet(tester, account, existing: container);

      // Real balance is $3.00: delta = 300 - (-500) = 800.
      await _typeDigits(tester, '300');
      await tester.pump();

      await tester.enterText(
        find.byKey(const Key('routeToIncomeSourceField')),
        'Cobro que faltaba',
      );
      await tester.pump();

      await tester.ensureVisible(
        find.byKey(const Key('routeToIncomeConfirmButton')),
      );
      await tester.tap(find.byKey(const Key('routeToIncomeConfirmButton')));
      await tester.pumpAndSettle();

      expect(projections.accountBalance(account.id).usd, 300);
      expect(projections.accountBalance(account.id).usd < 0, isFalse);
    });
  });
}
