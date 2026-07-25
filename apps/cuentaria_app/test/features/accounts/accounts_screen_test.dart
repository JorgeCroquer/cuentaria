import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:cuentaria_app/features/accounts/ui/screens/accounts_screen.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
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

  testWidgets('creates a USDT account and lists it with the USDT badge', (
    tester,
  ) async {
    await pumpAccountsScreen(tester);

    await tester.tap(find.byKey(const Key('addAccountFab')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('accountNameField')),
      'Binance',
    );
    await tester.tap(find.byKey(const Key('accountCurrencyDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('USDT').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saveAccountButton')));
    await tester.pumpAndSettle();

    expect(find.text('Binance'), findsOneWidget);
    expect(find.text('USDT'), findsOneWidget);
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
}
