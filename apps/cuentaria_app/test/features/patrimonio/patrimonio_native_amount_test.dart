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
    'shows each currency group\'s native total, not just USD equivalents '
    '(#114)',
    (tester) async {
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

      expect(
        tester
            .widget<Text>(find.byKey(const Key('accountGroupNativeAmount_VES')))
            .data,
        '1000.00 VES',
      );
    },
  );
}
