import 'package:cuentaria_app/features/reportes/ui/screens/reportes_screen.dart';
import 'package:cuentaria_app/main.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Reportes is reachable from a cold start via Patrimonio\'s AppBar '
    '(#258, #279)',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [isWebProvider.overrideWithValue(true)],
          child: const MyApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reportsAction')), findsOneWidget);

      await tester.tap(find.byKey(const Key('reportsAction')));
      await tester.pumpAndSettle();

      expect(find.byType(ReportesScreen), findsOneWidget);
    },
  );
}
