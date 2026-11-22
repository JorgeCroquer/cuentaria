import 'package:cuentaria_app/features/patrimonio/application/patrimonio_providers.dart';
import 'package:cuentaria_app/features/patrimonio/ui/screens/patrimonio_screen.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrimonio/patrimonio.dart';
import 'package:shared_kernel/shared_kernel.dart';

/// #333 "Ocultar saldos con un ojito": a single global eye toggle in
/// Patrimonio's header, hidden by default on every cold start.
void main() {
  ProviderContainer containerWithSnapshot() => ProviderContainer(
    overrides: [
      isWebProvider.overrideWithValue(true),
      patrimonioSnapshotProvider.overrideWith(
        (ref) async => PatrimonioSnapshot(
          realCostUsdCents: 123456,
          todayValueUsdCents: 123456,
          unrealizedPnlUsdCents: 0,
          bcvReferenceUsdCents: 123456,
          hasMissingRate: false,
          accountGroups: [
            PatrimonioAccountGroup(
              currency: CurrencyCode('USD'),
              nativeMinorAmount: BigInt.from(12345600),
              realCostUsdCents: 123456,
              todayValueUsdCents: 123456,
              bcvReferenceUsdCents: 123456,
              hasRate: true,
            ),
          ],
          envelopes: const [],
        ),
      ),
    ],
  );

  testWidgets(
    'cold start shows no digit in the hero amount — balances hidden by '
    'default (#333)',
    (tester) async {
      final container = containerWithSnapshot();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: PatrimonioScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final heroText =
          tester.widget<Text>(find.byKey(const Key('todayValueAmount'))).data!;
      expect(RegExp(r'\d').hasMatch(heroText), isFalse);
    },
  );

  testWidgets('tapping the eye icon reveals balances, tapping again hides '
      'them (#333)', (tester) async {
    final container = containerWithSnapshot();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PatrimonioScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const Key('todayValueAmount'))).data,
      '\$••••',
    );

    await tester.tap(find.byKey(const Key('hideBalancesAction')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const Key('todayValueAmount'))).data,
      '\$1234.56',
    );

    await tester.tap(find.byKey(const Key('hideBalancesAction')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const Key('todayValueAmount'))).data,
      '\$••••',
    );
  });
}
