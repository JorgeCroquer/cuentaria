import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:cuentaria_app/ui/ledger_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';

void main() {
  Future<void> pumpLedgerScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isWebProvider.overrideWithValue(true),
          catalogRepositoryProvider.overrideWith((ref) async {
            final repository = InMemoryCatalogRepository();
            await repository.saveAccount(
              Account(
                id: AccountId('test-acc'),
                name: 'Efectivo',
                nativeCurrency: CurrencyCode('USD'),
                isArchived: false,
                updatedAt: DateTime.now(),
              ),
            );
            return repository;
          }),
        ],
        child: const MaterialApp(home: LedgerScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the seeded account with a zero balance', (tester) async {
    await pumpLedgerScreen(tester);

    expect(find.text('Efectivo'), findsOneWidget);
    expect(find.text('\$0.00'), findsOneWidget);
  });

  testWidgets('renders the record form', (tester) async {
    await pumpLedgerScreen(tester);

    expect(find.byKey(const Key('amountField')), findsOneWidget);
    expect(find.byKey(const Key('envelopeDropdown')), findsOneWidget);
    expect(find.byKey(const Key('recordButton')), findsOneWidget);
  });

  testWidgets('recording a movement appends an event and updates the balance', (
    tester,
  ) async {
    await pumpLedgerScreen(tester);

    await tester.enterText(find.byKey(const Key('amountField')), '25.00');
    await tester.tap(find.byKey(const Key('recordButton')));
    await tester.pumpAndSettle();

    expect(find.text('\$25.00'), findsOneWidget);
    // The amount field is cleared after a successful recording.
    expect(find.text('25.00'), findsNothing);
  });

  testWidgets('rejects a non-positive amount without appending an event', (
    tester,
  ) async {
    await pumpLedgerScreen(tester);

    await tester.enterText(find.byKey(const Key('amountField')), '0');
    await tester.tap(find.byKey(const Key('recordButton')));
    await tester.pumpAndSettle();

    expect(find.text('\$0.00'), findsOneWidget);
    expect(find.textContaining('greater than zero'), findsOneWidget);
  });
}
