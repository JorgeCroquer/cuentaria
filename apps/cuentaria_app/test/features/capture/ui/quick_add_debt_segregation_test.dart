import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:cuentaria_app/features/capture/ui/screens/quick_add_expense_sheet.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';

/// #208: the Gasto/Ingreso pickers hide Debt Accounts (condoning happens
/// from Deudas, not as a daily "gastar desde Pedro" flow); the Mover picker
/// lists them at the end under a "Deudas" section, since Prestar/Cobrar are
/// modeled as transfers into/out of a Debt Account.
Future<ProviderContainer> _pumpSheet(WidgetTester tester) async {
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

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: QuickAddExpenseSheet())),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('Gasto picker does not list Pedro (a Debt Account)', (
    tester,
  ) async {
    await _pumpSheet(tester);

    expect(find.byKey(const Key('accountChip_efectivo')), findsOneWidget);
    expect(find.byKey(const Key('accountChip_pedro')), findsNothing);
  });

  testWidgets('Ingreso picker does not list Pedro (a Debt Account)', (
    tester,
  ) async {
    await _pumpSheet(tester);

    await tester.tap(find.byKey(const Key('captureModeIngreso')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('incomeAccountChip_efectivo')), findsOneWidget);
    expect(find.byKey(const Key('incomeAccountChip_pedro')), findsNothing);
  });

  testWidgets(
    'Mover picker lists Pedro at the end, under a "Deudas" section, for '
    'both Desde and Hacia',
    (tester) async {
      await _pumpSheet(tester);

      await tester.tap(find.byKey(const Key('captureModeMover')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('moverSourceChip_efectivo')), findsOneWidget);
      expect(find.byKey(const Key('moverSourceChip_pedro')), findsOneWidget);
      expect(
        find.byKey(const Key('moverDestinationChip_efectivo')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('moverDestinationChip_pedro')),
        findsOneWidget,
      );
      expect(find.text('Deudas'), findsNWidgets(2));

      final efectivoCenter = tester.getCenter(
        find.byKey(const Key('moverSourceChip_efectivo')),
      );
      final pedroCenter = tester.getCenter(
        find.byKey(const Key('moverSourceChip_pedro')),
      );
      expect(pedroCenter.dy, greaterThan(efectivoCenter.dy));
    },
  );
}
