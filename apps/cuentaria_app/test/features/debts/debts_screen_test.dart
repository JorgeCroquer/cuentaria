import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:cuentaria_app/features/debts/ui/screens/debts_screen.dart';
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
      child: const MaterialApp(home: DebtsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  Future<ProviderContainer> pumpDebtsScreen(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [isWebProvider.overrideWithValue(true)],
    );
    addTearDown(container.dispose);
    await pumpWithContainer(tester, container);
    return container;
  }

  testWidgets('shows the empty state with a CTA when there are no people', (
    tester,
  ) async {
    await pumpDebtsScreen(tester);

    expect(find.byKey(const Key('debtsEmptyState')), findsOneWidget);
    expect(find.byKey(const Key('createPersonCta')), findsOneWidget);
  });

  testWidgets('creates Pedro in USD and lists him', (tester) async {
    final container = await pumpDebtsScreen(tester);

    await tester.tap(find.byKey(const Key('createPersonCta')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('personNameField')), 'Pedro');
    await tester.tap(find.byKey(const Key('savePersonButton')));
    await tester.pumpAndSettle();

    expect(find.text('Pedro'), findsOneWidget);
    expect(find.byKey(const Key('debtsEmptyState')), findsNothing);

    final catalog = await container.read(catalogRepositoryProvider.future);
    final account = catalog.accounts.singleWhere((a) => a.name == 'Pedro');
    expect(account.counterpartyName, 'Pedro');
    expect(account.nativeCurrency, CurrencyCode('USD'));
  });

  testWidgets('creates Ana in VES and lists her below Pedro', (tester) async {
    final container = await pumpDebtsScreen(tester);

    await tester.tap(find.byKey(const Key('createPersonCta')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('personNameField')), 'Pedro');
    await tester.tap(find.byKey(const Key('savePersonButton')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('addPersonFab')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('personNameField')), 'Ana');
    await tester.tap(find.byKey(const Key('personCurrencyDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('VES').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('savePersonButton')));
    await tester.pumpAndSettle();

    expect(find.text('Pedro'), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget);

    final catalog = await container.read(catalogRepositoryProvider.future);
    final ana = catalog.accounts.singleWhere((a) => a.name == 'Ana');
    expect(ana.nativeCurrency, CurrencyCode('VES'));
  });

  testWidgets('a debt account starts with a zero opening balance — no '
      'ledger transaction is posted', (tester) async {
    final container = await pumpDebtsScreen(tester);

    await tester.tap(find.byKey(const Key('createPersonCta')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('personNameField')), 'Pedro');
    await tester.tap(find.byKey(const Key('savePersonButton')));
    await tester.pumpAndSettle();

    final store = await container.read(eventStoreProvider.future);
    expect(await store.queryLog(), isEmpty);
  });

  testWidgets('rejects an empty name without creating a person', (
    tester,
  ) async {
    await pumpDebtsScreen(tester);

    await tester.tap(find.byKey(const Key('createPersonCta')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('savePersonButton')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Name is required'), findsOneWidget);
    expect(find.byKey(const Key('debtsEmptyState')), findsOneWidget);
  });

  testWidgets('does not list regular (non-debt) accounts', (tester) async {
    final container = ProviderContainer(
      overrides: [isWebProvider.overrideWithValue(true)],
    );
    addTearDown(container.dispose);
    final catalog = await container.read(catalogRepositoryProvider.future);
    await catalog.saveAccount(
      Account(
        id: AccountId('acc-1'),
        name: 'Binance',
        nativeCurrency: CurrencyCode('USD'),
        isArchived: false,
        updatedAt: DateTime.now(),
      ),
    );

    await pumpWithContainer(tester, container);

    expect(find.text('Binance'), findsNothing);
    expect(find.byKey(const Key('debtsEmptyState')), findsOneWidget);
  });
}
