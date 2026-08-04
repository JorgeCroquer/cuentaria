import 'package:cuentaria_app/features/patrimonio/application/patrimonio_providers.dart';
import 'package:cuentaria_app/features/patrimonio/ui/screens/patrimonio_screen.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrimonio/patrimonio.dart';
import 'package:shared_kernel/shared_kernel.dart';

void main() {
  testWidgets(
    'signals a negative currency-group balance as a cause hint, not a '
    'bare number (#113)',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          isWebProvider.overrideWithValue(true),
          patrimonioSnapshotProvider.overrideWith(
            (ref) async => PatrimonioSnapshot(
              realCostUsdCents: 0,
              todayValueUsdCents: -50,
              unrealizedPnlUsdCents: -50,
              bcvReferenceUsdCents: 0,
              hasMissingRate: false,
              accountGroups: [
                PatrimonioAccountGroup(
                  currency: CurrencyCode('VES'),
                  nativeMinorAmount: BigInt.from(-5000),
                  realCostUsdCents: 0,
                  todayValueUsdCents: -125,
                  bcvReferenceUsdCents: -125,
                  hasRate: true,
                ),
              ],
              envelopes: const [],
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: PatrimonioScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(find.byKey(const Key('accountGroupNativeAmount_VES')))
            .data,
        '-50.00 VES',
      );
      expect(
        find.byKey(const Key('negativeBalanceSignal_VES')),
        findsOneWidget,
      );
      expect(
        find.text('Saldo negativo — ¿falta registrar un ingreso?'),
        findsOneWidget,
      );
    },
  );

  testWidgets('does not show the negative-balance signal for a positive '
      'group (#113)', (tester) async {
    final container = ProviderContainer(
      overrides: [
        isWebProvider.overrideWithValue(true),
        patrimonioSnapshotProvider.overrideWith(
          (ref) async => PatrimonioSnapshot(
            realCostUsdCents: 1000,
            todayValueUsdCents: 1000,
            unrealizedPnlUsdCents: 0,
            bcvReferenceUsdCents: 1000,
            hasMissingRate: false,
            accountGroups: [
              PatrimonioAccountGroup(
                currency: CurrencyCode('VES'),
                nativeMinorAmount: BigInt.from(100000),
                realCostUsdCents: 1000,
                todayValueUsdCents: 1000,
                bcvReferenceUsdCents: 1000,
                hasRate: true,
              ),
            ],
            envelopes: const [],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PatrimonioScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('negativeBalanceSignal_VES')), findsNothing);
  });
}
