import 'package:cuentaria_app/features/envelopes/ui/screens/envelope_edit_screen.dart';
import 'package:cuentaria_app/features/envelopes/ui/screens/envelopes_list_screen.dart';
import 'package:cuentaria_app/main.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Envelopes are reachable from a cold start via Patrimonio (#95)',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [isWebProvider.overrideWithValue(true)],
          child: const MyApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('manageEnvelopesAction')));
      await tester.pumpAndSettle();

      expect(find.byType(EnvelopesListScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('createEnvelopeButton')));
      await tester.pumpAndSettle();

      expect(find.byType(EnvelopeEditScreen), findsOneWidget);

      await tester.enterText(find.byKey(const Key('nameField')), 'Mercado');
      await tester.tap(find.byKey(const Key('saveEnvelopeButton')));
      await tester.pumpAndSettle();

      expect(find.byType(EnvelopesListScreen), findsOneWidget);
      expect(find.text('Mercado'), findsOneWidget);
    },
  );
}
