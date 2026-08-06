import 'package:cuentaria_app/features/patrimonio/application/patrimonio_providers.dart';
import 'package:cuentaria_app/features/patrimonio/ui/screens/patrimonio_screen.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrimonio/patrimonio.dart';
import 'package:shared_kernel/shared_kernel.dart';

/// #177: the Envelope list shows balances at frozen real cost (ADR-0006),
/// while the header shows today's value — a section label must declare
/// this so the two figures don't read as an inconsistency.
void main() {
  testWidgets(
    'labels the Envelope list as frozen cost, distinct from the header\'s '
    'today value',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          isWebProvider.overrideWithValue(true),
          patrimonioSnapshotProvider.overrideWith(
            (ref) async => PatrimonioSnapshot(
              realCostUsdCents: 944,
              todayValueUsdCents: 889,
              unrealizedPnlUsdCents: -55,
              bcvReferenceUsdCents: 944,
              hasMissingRate: false,
              accountGroups: [
                PatrimonioAccountGroup(
                  currency: CurrencyCode('VES'),
                  nativeMinorAmount: BigInt.from(800000),
                  realCostUsdCents: 944,
                  todayValueUsdCents: 889,
                  bcvReferenceUsdCents: 944,
                  hasRate: true,
                  hasBcvRate: true,
                  parallelRate: null,
                  bcvRate: null,
                ),
              ],
              envelopes: [
                PatrimonioEnvelope(
                  id: EnvelopeId('mercado'),
                  name: 'Mercado',
                  role: EnvelopeRoleView.user,
                  balanceUsd: 944,
                  target: const NoTargetView(),
                  metadata: const NoMetadata(),
                ),
              ],
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

      expect(find.byKey(const Key('envelopesFrozenCostLabel')), findsOneWidget);
    },
  );
}
