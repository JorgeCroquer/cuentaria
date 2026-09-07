import 'package:cuentaria_app/features/reportes/ui/screens/reportes_screen.dart';
import 'package:cuentaria_app/main.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Reportes is reachable from a cold start via Patrimonio\'s overflow '
    'menu, next to Deudas (#258)',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [isWebProvider.overrideWithValue(true)],
          child: const MyApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('patrimonioOverflowMenu')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reportsMenuItem')), findsOneWidget);

      await tester.tap(find.byKey(const Key('reportsMenuItem')));
      await tester.pumpAndSettle();

      expect(find.byType(ReportesScreen), findsOneWidget);
    },
  );
}
