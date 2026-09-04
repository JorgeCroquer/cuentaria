import 'package:cuentaria_app/features/cloud_copy/ui/screens/cloud_copy_screen.dart';
import 'package:cuentaria_app/main.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'the empty state offers a link to connect Google Drive and routes to '
    '/cloud-copy',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [isWebProvider.overrideWithValue(true)],
          child: const MyApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('patrimonioEmptyState')), findsOneWidget);
      expect(
        find.text(
          '¿Ya usás Cuentaria en otro teléfono? Conectá tu Google Drive',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('cloudCopyEmptyStateLink')));
      await tester.pumpAndSettle();

      expect(find.byType(CloudCopyScreen), findsOneWidget);
    },
  );
}
