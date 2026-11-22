import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/catalog/models/funding_target.dart';
import 'package:cuentaria_app/features/envelopes/ui/screens/envelopes_list_screen.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';

/// #333: balances hidden by default means Sobres' Tope/Meta summary shows
/// no digit either.
void main() {
  testWidgets(
    'shows no digit in the Tope summary while balances are hidden (#333)',
    (tester) async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      final catalog = await container.read(catalogRepositoryProvider.future);
      await catalog.saveEnvelope(
        Envelope(
          id: EnvelopeId('mercado'),
          name: 'Mercado',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        ).withTarget(const Cap(amountUsd: 30000)),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: EnvelopesListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final summary = tester.widget<Text>(find.textContaining('Tope:')).data!;
      expect(RegExp(r'\d').hasMatch(summary), isFalse);
    },
  );
}
