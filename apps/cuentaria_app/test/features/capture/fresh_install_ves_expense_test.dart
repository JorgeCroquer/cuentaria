import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:cuentaria_app/features/accounts/ui/screens/accounts_screen.dart';
import 'package:cuentaria_app/features/capture/ui/screens/quick_add_expense_sheet.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';

void main() {
  testWidgets(
    'fresh install: creating a Bs account with an opening balance lets a Bs '
    'expense save without RateNotAvailable (#112)',
    (tester) async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      // Fresh install: only an envelope pre-exists to capture into, no
      // accounts, no rates — mirrors the U1 onboarding starting point.
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

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AccountsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Same moment U1-13 already asks for the opening rate — one step.
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

      // Golden path (#97): FAB → amount → Save.
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
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('openSheetButton')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('keypadDigit_5')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('quickAddSaveButton')));
      await tester.tap(find.byKey(const Key('quickAddSaveButton')));
      await tester.pumpAndSettle();

      expect(find.textContaining('RateNotAvailable'), findsNothing);
      expect(find.textContaining('No hay tasa registrada'), findsNothing);
      expect(find.byKey(const Key('numericKeypad')), findsNothing);
    },
  );
}
