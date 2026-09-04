import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:cuentaria_app/features/capture/ui/screens/quick_add_expense_sheet.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';

/// #208: Prestar/Cobrar/Condonar from Deudas open the existing capture
/// flows with a Debt Account preselected — no new factories, only
/// preselection + which mode the sheet opens on.
Future<ProviderContainer> _seededContainer() async {
  final container = ProviderContainer(
    overrides: [isWebProvider.overrideWithValue(true)],
  );
  addTearDown(container.dispose);

  final catalog = await container.read(catalogRepositoryProvider.future);
  await catalog.saveAccount(
    Account(
      id: AccountId('efectivo'),
      name: 'Efectivo',
      nativeCurrency: CurrencyCode('USD'),
      isArchived: false,
      updatedAt: DateTime.now(),
    ),
  );
  await catalog.saveAccount(
    Account(
      id: AccountId('pedro'),
      name: 'Pedro',
      nativeCurrency: CurrencyCode('USD'),
      isArchived: false,
      updatedAt: DateTime.now(),
      meta: {'counterpartyName': 'Pedro'},
    ),
  );
  await catalog.saveEnvelope(
    Envelope(
      id: EnvelopeId('comida'),
      name: 'Comida',
      role: EnvelopeRole.none,
      isArchived: false,
      updatedAt: DateTime.now(),
    ),
  );
  return container;
}

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container,
  Widget sheet,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: sheet)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Prestar preselects Mover with Pedro as the destination', (
    tester,
  ) async {
    final container = await _seededContainer();
    await _pump(
      tester,
      container,
      QuickAddExpenseSheet(
        preselectedMoverDestinationAccountId: AccountId('pedro'),
      ),
    );

    expect(find.byKey(const Key('moverStep1')), findsOneWidget);
    final destinationChip = tester.widget<ChoiceChip>(
      find.byKey(const Key('moverDestinationChip_pedro')),
    );
    expect(destinationChip.selected, isTrue);
  });

  testWidgets('Cobrar preselects Mover with Pedro as the source', (
    tester,
  ) async {
    final container = await _seededContainer();
    await _pump(
      tester,
      container,
      QuickAddExpenseSheet(preselectedMoverSourceAccountId: AccountId('pedro')),
    );

    expect(find.byKey(const Key('moverStep1')), findsOneWidget);
    final sourceChip = tester.widget<ChoiceChip>(
      find.byKey(const Key('moverSourceChip_pedro')),
    );
    expect(sourceChip.selected, isTrue);
  });

  testWidgets(
    'Condonar preselects Gasto with Pedro as the paying account, letting '
    'the user pick the envelope',
    (tester) async {
      final container = await _seededContainer();
      await _pump(
        tester,
        container,
        QuickAddExpenseSheet(preselectedGastoAccountId: AccountId('pedro')),
      );

      expect(find.byKey(const Key('captureModeGasto')), findsOneWidget);
      final gastoChip = tester.widget<ChoiceChip>(
        find.byKey(const Key('captureModeGasto')),
      );
      expect(gastoChip.selected, isTrue);

      // The preselection must be VISIBLE: Debt Accounts are excluded from
      // the Gasto picker (#208), so without its own chip Pedro was selected
      // invisibly and any tap on a visible chip silently dropped the
      // condonación (device finding, 2026-09-04).
      final pedroChip = tester.widget<ChoiceChip>(
        find.byKey(const Key('accountChip_pedro')),
      );
      expect(pedroChip.selected, isTrue);

      await tester.tap(find.byKey(const Key('keypadDigit_5')));
      await tester.tap(find.byKey(const Key('envelopeChip_comida')));
      await tester.pump();

      final saveButton = tester.widget<ElevatedButton>(
        find.byKey(const Key('quickAddSaveButton')),
      );
      expect(saveButton.onPressed, isNotNull);
    },
  );
}
