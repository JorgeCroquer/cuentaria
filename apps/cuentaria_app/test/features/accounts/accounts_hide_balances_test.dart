import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:cuentaria_app/features/accounts/ui/screens/accounts_screen.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';

/// #333: balances hidden by default means Cuentas shows no digit either.
void main() {
  testWidgets('shows no digit in an account balance while hidden (#333)', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [isWebProvider.overrideWithValue(true)],
    );
    addTearDown(container.dispose);

    final catalog = await container.read(catalogRepositoryProvider.future);
    final accountId = AccountId('acc-1');
    await catalog.saveAccount(
      Account(
        id: accountId,
        name: 'Efectivo',
        nativeCurrency: CurrencyCode('USD'),
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

    final balanceText =
        tester
            .widget<Text>(find.byKey(Key('accountBalance_${accountId.value}')))
            .data!;
    expect(RegExp(r'\d').hasMatch(balanceText), isFalse);
  });
}
