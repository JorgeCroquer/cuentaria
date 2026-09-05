import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:cuentaria_app/features/accounts/ui/screens/accounts_screen.dart';
import 'package:cuentaria_app/features/capture/ui/screens/quick_add_expense_sheet.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';

/// Roots both screens under one container/navigator so a catalog mutation
/// made through Cuentas and a quick-add sheet opened right after share
/// provider state — reproducing the same-session bug (#243) instead of a
/// synthetic provider-only check.
Future<ProviderContainer> _pumpAccountsAndQuickAdd(WidgetTester tester) async {
  final container = ProviderContainer(
    overrides: [isWebProvider.overrideWithValue(true)],
  );
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
                body: Center(
                  child: ElevatedButton(
                    key: const Key('openAccountsButton'),
                    onPressed:
                        () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AccountsScreen(),
                          ),
                        ),
                    child: const Text('Cuentas'),
                  ),
                ),
              ),
        ),
      ),
    ),
  );

  return container;
}

void main() {
  testWidgets(
    'a just-created account appears in the quick-add sheet in the same '
    'session, without reopening the app (#243)',
    (tester) async {
      await _pumpAccountsAndQuickAdd(tester);

      // Open the sheet once so quickAddCaptureContextProvider builds and
      // caches its snapshot before the account exists — reproducing the bug,
      // where the very first open already primed a stale cache.
      await tester.tap(find.byKey(const Key('openSheetButton')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(1, 1));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('openAccountsButton')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('addAccountFab')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('accountNameField')),
        'Binance',
      );
      await tester.tap(find.byKey(const Key('saveAccountButton')));
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('openSheetButton')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Binance'), findsOneWidget);
    },
  );

  testWidgets(
    'a just-renamed account shows its new name in the quick-add sheet in the '
    'same session (#243)',
    (tester) async {
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
                    body: Center(
                      child: ElevatedButton(
                        key: const Key('openAccountsButton'),
                        onPressed:
                            () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const AccountsScreen(),
                              ),
                            ),
                        child: const Text('Cuentas'),
                      ),
                    ),
                  ),
            ),
          ),
        ),
      );

      // Prime the sheet's cache with the pre-rename catalog, same as above.
      await tester.tap(find.byKey(const Key('openSheetButton')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(1, 1));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('openAccountsButton')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('editAccount_acc-1')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('accountNameField')),
        'New name',
      );
      await tester.tap(find.byKey(const Key('saveAccountButton')));
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('openSheetButton')));
      await tester.pumpAndSettle();

      expect(find.textContaining('New name'), findsOneWidget);
      expect(find.textContaining('Old name'), findsNothing);
    },
  );
}
