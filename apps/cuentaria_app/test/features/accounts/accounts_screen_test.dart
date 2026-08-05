import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:cuentaria_app/features/accounts/ui/screens/accounts_screen.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:cuentaria_app/providers/tasas_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';

Future<void> pumpWithContainer(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AccountsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  Future<ProviderContainer> pumpAccountsScreen(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [isWebProvider.overrideWithValue(true)],
    );
    addTearDown(container.dispose);
    await pumpWithContainer(tester, container);
    return container;
  }

  testWidgets('shows empty-state guidance when there are no accounts', (
    tester,
  ) async {
    await pumpAccountsScreen(tester);

    expect(find.byKey(const Key('accountsEmptyState')), findsOneWidget);
  });

  testWidgets('creates an account with a name, currency and color', (
    tester,
  ) async {
    await pumpAccountsScreen(tester);

    await tester.tap(find.byKey(const Key('addAccountFab')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('accountNameField')),
      'Binance',
    );
    await tester.tap(find.byKey(const Key('colorSwatch_#1E8E5A')));
    await tester.tap(find.byKey(const Key('saveAccountButton')));
    await tester.pumpAndSettle();

    expect(find.text('Binance'), findsOneWidget);
    expect(find.text('USD'), findsOneWidget);
  });

  testWidgets('creates a Binance account as USD and lists it', (tester) async {
    await pumpAccountsScreen(tester);

    await tester.tap(find.byKey(const Key('addAccountFab')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('accountNameField')),
      'Binance',
    );
    await tester.tap(find.byKey(const Key('accountCurrencyDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('USD').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saveAccountButton')));
    await tester.pumpAndSettle();

    expect(find.text('Binance'), findsOneWidget);
    expect(find.text('USD'), findsOneWidget);
  });

  testWidgets('a non-zero opening balance posts to the Apertura envelope', (
    tester,
  ) async {
    final container = await pumpAccountsScreen(tester);

    await tester.tap(find.byKey(const Key('addAccountFab')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('accountNameField')),
      'Bancamiga',
    );
    await tester.enterText(find.byKey(const Key('openingBalanceField')), '200');
    await tester.tap(find.byKey(const Key('saveAccountButton')));
    await tester.pumpAndSettle();

    final catalog = await container.read(catalogRepositoryProvider.future);
    final projections = container.read(ledgerProjectionsProvider);
    final account = catalog.accounts.singleWhere((a) => a.name == 'Bancamiga');

    expect(projections.accountBalance(account.id).usd, 20000);
  });

  testWidgets(
    'shows each account\'s current balance in its native currency (#114)',
    (tester) async {
      final container = await pumpAccountsScreen(tester);

      await tester.tap(find.byKey(const Key('addAccountFab')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('accountNameField')), 'BdV');
      await tester.tap(find.byKey(const Key('accountCurrencyDropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('VES').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('openingBalanceField')),
        '1000',
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('openingBalanceRateField')),
        '100',
      );
      await tester.tap(find.byKey(const Key('saveAccountButton')));
      await tester.pumpAndSettle();

      final catalog = await container.read(catalogRepositoryProvider.future);
      final account = catalog.accounts.singleWhere((a) => a.name == 'BdV');

      expect(
        tester
            .widget<Text>(find.byKey(Key('accountBalance_${account.id.value}')))
            .data,
        '1000.00 VES',
      );
    },
  );

  testWidgets(
    'signals a negative balance with an indicator and a cause hint (#113)',
    (tester) async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);
      final catalog = await container.read(catalogRepositoryProvider.future);
      final account = Account(
        id: AccountId('acc-sobregiro'),
        name: 'Bs sobregiro',
        nativeCurrency: CurrencyCode('VES'),
        isArchived: false,
        updatedAt: DateTime.now(),
      );
      await catalog.saveAccount(account);

      final store = await container.read(eventStoreProvider.future);
      final projections = container.read(ledgerProjectionsProvider);
      final tx = Transaction.create(
        metadata: TransactionMetadata(
          eventId: EventId('evt-sobregiro'),
          type: 'ForeignCurrencyExpense',
          occurredAt: DomainTimestamp(DateTime.now().toUtc()),
          recordedAt: DomainTimestamp(DateTime.now().toUtc()),
          deviceId: 'dev',
          schemaVersion: 1,
        ),
        postings: [
          Posting(
            target: AccountTarget(account.id),
            amountNative: Money(
              amount: BigInt.from(-5000),
              currency: CurrencyCode('VES'),
            ),
            currency: CurrencyCode('VES'),
            amountUsd: -125,
          ),
          Posting(
            target: EnvelopeTarget(
              catalog.getSystemEnvelope(EnvelopeRole.differential),
            ),
            amountNative: Money(
              amount: BigInt.from(-125),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: -125,
          ),
        ],
      );
      await store.append(tx);
      projections.apply(tx);

      await pumpWithContainer(tester, container);

      expect(
        find.byKey(Key('negativeBalanceIndicator_${account.id.value}')),
        findsOneWidget,
      );
      final tooltip = tester.widget<Tooltip>(
        find.ancestor(
          of: find.byKey(Key('negativeBalanceIndicator_${account.id.value}')),
          matching: find.byType(Tooltip),
        ),
      );
      expect(tooltip.message, 'Saldo negativo — ¿falta registrar un ingreso?');
    },
  );

  testWidgets('rejects an empty name without creating an account', (
    tester,
  ) async {
    await pumpAccountsScreen(tester);

    await tester.tap(find.byKey(const Key('addAccountFab')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('saveAccountButton')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Name is required'), findsOneWidget);
    expect(find.byKey(const Key('accountsEmptyState')), findsOneWidget);
  });

  testWidgets('requires an exchange rate for a non-USD opening balance', (
    tester,
  ) async {
    await pumpAccountsScreen(tester);

    await tester.tap(find.byKey(const Key('addAccountFab')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('accountNameField')), 'BdV');
    await tester.tap(find.byKey(const Key('accountCurrencyDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('VES').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('openingBalanceField')), '350');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saveAccountButton')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Exchange rate is required'), findsOneWidget);
    expect(find.byKey(const Key('accountsEmptyState')), findsOneWidget);
  });

  testWidgets('a non-USD opening balance with an exchange rate posts the '
      'USD-equivalent to the Apertura envelope', (tester) async {
    final container = await pumpAccountsScreen(tester);

    await tester.tap(find.byKey(const Key('addAccountFab')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('accountNameField')), 'BdV');
    await tester.tap(find.byKey(const Key('accountCurrencyDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('VES').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('openingBalanceField')), '350');
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('openingBalanceRateField')),
      '3.5',
    );
    await tester.tap(find.byKey(const Key('saveAccountButton')));
    await tester.pumpAndSettle();

    final catalog = await container.read(catalogRepositoryProvider.future);
    final projections = container.read(ledgerProjectionsProvider);
    final account = catalog.accounts.singleWhere((a) => a.name == 'BdV');

    expect(projections.accountBalance(account.id).usd, 10000);
  });

  testWidgets('requires an exchange rate for a non-USD account even without an '
      'opening balance (#112)', (tester) async {
    await pumpAccountsScreen(tester);

    await tester.tap(find.byKey(const Key('addAccountFab')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('accountNameField')), 'BdV');
    await tester.tap(find.byKey(const Key('accountCurrencyDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('VES').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saveAccountButton')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Exchange rate is required'), findsOneWidget);
    expect(find.byKey(const Key('accountsEmptyState')), findsOneWidget);
  });

  testWidgets(
    'the opening rate is also recorded as a parallel-rate observation so a '
    'Bs expense never hits RateNotAvailable (#112)',
    (tester) async {
      final container = await pumpAccountsScreen(tester);

      await tester.tap(find.byKey(const Key('addAccountFab')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('accountNameField')), 'BdV');
      await tester.tap(find.byKey(const Key('accountCurrencyDropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('VES').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('openingBalanceField')),
        '350',
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('openingBalanceRateField')),
        '3.5',
      );
      await tester.tap(find.byKey(const Key('saveAccountButton')));
      await tester.pumpAndSettle();

      final rateSeries = await container.read(rateSeriesProvider.future);
      final observation = await rateSeries.latestFor(
        CurrencyCode('VES'),
        source: 'manual:paralelo',
      );

      expect(observation, isNotNull);
      expect(observation!.nativePerUsd.toString(), '3.5');
    },
  );

  testWidgets(
    'a non-USD account created without an opening balance still records '
    "today's rate as an observation (#112)",
    (tester) async {
      final container = await pumpAccountsScreen(tester);

      await tester.tap(find.byKey(const Key('addAccountFab')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('accountNameField')), 'BdV');
      await tester.tap(find.byKey(const Key('accountCurrencyDropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('VES').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('openingBalanceRateField')),
        '90',
      );
      await tester.tap(find.byKey(const Key('saveAccountButton')));
      await tester.pumpAndSettle();

      final catalog = await container.read(catalogRepositoryProvider.future);
      expect(catalog.accounts.any((a) => a.name == 'BdV'), isTrue);

      final rateSeries = await container.read(rateSeriesProvider.future);
      final observation = await rateSeries.latestFor(
        CurrencyCode('VES'),
        source: 'manual:paralelo',
      );

      expect(observation, isNotNull);
      expect(observation!.nativePerUsd.toString(), '90');
    },
  );

  testWidgets('rejects a decimal opening balance', (tester) async {
    await pumpAccountsScreen(tester);

    await tester.tap(find.byKey(const Key('addAccountFab')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('accountNameField')), 'Test');
    await tester.enterText(
      find.byKey(const Key('openingBalanceField')),
      '100.50',
    );
    await tester.tap(find.byKey(const Key('saveAccountButton')));
    await tester.pumpAndSettle();

    expect(find.textContaining('whole number'), findsOneWidget);
  });

  testWidgets('editing an account updates its name reactively', (tester) async {
    final container = ProviderContainer(
      overrides: [isWebProvider.overrideWithValue(true)],
    );
    addTearDown(container.dispose);
    final catalog = await container.read(catalogRepositoryProvider.future);
    await catalog.saveAccount(
      Account(
        id: AccountId('acc-1'),
        name: 'Old name',
        nativeCurrency: CurrencyCode('USD'),
        isArchived: false,
        updatedAt: DateTime.now(),
      ),
    );

    await pumpWithContainer(tester, container);
    expect(find.text('Old name'), findsOneWidget);

    await tester.tap(find.byKey(const Key('editAccount_acc-1')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('accountNameField')),
      'New name',
    );
    await tester.tap(find.byKey(const Key('saveAccountButton')));
    await tester.pumpAndSettle();

    expect(find.text('New name'), findsOneWidget);
    expect(find.text('Old name'), findsNothing);
  });

  testWidgets('archiving an account removes it from the list', (tester) async {
    final container = ProviderContainer(
      overrides: [isWebProvider.overrideWithValue(true)],
    );
    addTearDown(container.dispose);
    final catalog = await container.read(catalogRepositoryProvider.future);
    await catalog.saveAccount(
      Account(
        id: AccountId('acc-1'),
        name: 'Old wallet',
        nativeCurrency: CurrencyCode('USD'),
        isArchived: false,
        updatedAt: DateTime.now(),
      ),
    );

    await pumpWithContainer(tester, container);
    expect(find.text('Old wallet'), findsOneWidget);

    await tester.tap(find.byKey(const Key('archiveAccount_acc-1')));
    await tester.pumpAndSettle();

    expect(find.text('Old wallet'), findsNothing);
    expect(find.byKey(const Key('accountsEmptyState')), findsOneWidget);
    expect(catalog.getAccount(AccountId('acc-1'))?.isArchived, isTrue);
  });

  testWidgets(
    'tapping an account row opens the Reconciliation sheet for it (#147)',
    (tester) async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);
      final catalog = await container.read(catalogRepositoryProvider.future);
      await catalog.saveAccount(
        Account(
          id: AccountId('acc-1'),
          name: 'Bancamiga',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      await pumpWithContainer(tester, container);

      await tester.tap(find.byKey(const Key('account_acc-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('projectedBalanceText')), findsOneWidget);
    },
  );
}
