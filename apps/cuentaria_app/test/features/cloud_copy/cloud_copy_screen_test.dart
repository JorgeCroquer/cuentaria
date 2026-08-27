import 'package:backup/infrastructure/in_memory_cloud_folder.dart';
import 'package:cuentaria_app/features/cloud_copy/application/cloud_copy_providers.dart';
import 'package:cuentaria_app/features/cloud_copy/ui/screens/cloud_copy_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cloud_copy_test_support.dart';

Future<void> _pumpScreen(
  WidgetTester tester, {
  required dynamic override,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [override],
      child: const MaterialApp(home: CloudCopyScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(ensureSqlite3ForTests);

  final successOverride = cloudCopyUseCaseProvider.overrideWith(
    (ref) async =>
        buildTestCloudCopyUseCase(cloudFolder: InMemoryCloudFolder()),
  );

  final failureOverride = cloudCopyUseCaseProvider.overrideWith(
    (ref) async => buildTestCloudCopyUseCase(
      cloudFolder: const FailingCloudFolder('sin internet'),
    ),
  );

  testWidgets('initial render shows transparency text and Conectar button', (
    tester,
  ) async {
    await _pumpScreen(tester, override: successOverride);

    expect(
      find.text(
        'Cuentaria guarda una copia de tus datos en TU Google Drive, en '
        'una carpeta que solo esta app ve. No tenemos servidor: no vemos, '
        'no guardamos y no podemos recuperar tus datos.',
      ),
      findsOneWidget,
    );
    expect(find.text('Conectar mi Google Drive'), findsOneWidget);
    expect(find.text('Copiar ahora'), findsOneWidget);
  });

  testWidgets(
    'tapping Conectar shows the account, flips to Desconectar and syncs',
    (tester) async {
      await _pumpScreen(tester, override: successOverride);

      await tester.tap(find.byKey(const Key('connectGoogleDriveButton')));
      await tester.pumpAndSettle();

      expect(find.text('cuenta de prueba'), findsOneWidget);
      expect(find.text('Desconectar'), findsOneWidget);
      expect(find.text('Copia en Drive: hace un momento'), findsOneWidget);
    },
  );

  testWidgets('tapping Copiar ahora runs a sync and shows success', (
    tester,
  ) async {
    await _pumpScreen(tester, override: successOverride);
    await tester.tap(find.byKey(const Key('connectGoogleDriveButton')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('copyNowButton')));
    await tester.pumpAndSettle();

    expect(find.text('Copia en Drive: hace un momento'), findsOneWidget);
  });

  testWidgets('a failing CloudFolder shows the error label and retry works', (
    tester,
  ) async {
    await _pumpScreen(tester, override: failureOverride);

    await tester.tap(find.byKey(const Key('connectGoogleDriveButton')));
    await tester.pumpAndSettle();

    expect(
      find.text('Falló hace un momento: sin internet — tocá para reintentar'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('cloudStatusLabel')));
    await tester.pumpAndSettle();

    expect(
      find.text('Falló hace un momento: sin internet — tocá para reintentar'),
      findsOneWidget,
    );
  });

  testWidgets(
    'tapping Desconectar resets to the initial state without touching data',
    (tester) async {
      await _pumpScreen(tester, override: successOverride);
      await tester.tap(find.byKey(const Key('connectGoogleDriveButton')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('disconnectButton')));
      await tester.pumpAndSettle();

      expect(find.text('Conectar mi Google Drive'), findsOneWidget);
      expect(find.text('cuenta de prueba'), findsNothing);
      expect(find.text('Copia en Drive: nunca'), findsOneWidget);
    },
  );
}
