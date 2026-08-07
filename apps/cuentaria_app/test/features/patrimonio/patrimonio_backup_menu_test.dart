import 'package:cuentaria_app/features/backup/ui/screens/backup_screen.dart';
import 'package:cuentaria_app/main.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the ⋮ overflow menu offers Respaldo and routes to /backup', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [isWebProvider.overrideWithValue(true)],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('patrimonioOverflowMenu')), findsOneWidget);

    await tester.tap(find.byKey(const Key('patrimonioOverflowMenu')));
    await tester.pumpAndSettle();

    expect(find.text('Respaldo'), findsOneWidget);

    await tester.tap(find.byKey(const Key('backupMenuItem')));
    await tester.pumpAndSettle();

    expect(find.byType(BackupScreen), findsOneWidget);
  });
}
