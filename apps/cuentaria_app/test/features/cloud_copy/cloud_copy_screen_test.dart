import 'package:backup/domain/ports/cloud_folder.dart';
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
  FakeGoogleDriveSession? session,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        override,
        googleDriveSessionProvider.overrideWithValue(
          session ?? FakeGoogleDriveSession(),
        ),
      ],
      child: const MaterialApp(home: CloudCopyScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

/// A [CloudFolder] that revokes [session] and reports it on its first call
/// only, then works normally — the shape of a Google Drive session an
/// account owner revoked from Google's side and then reconnected (issue
/// #225 AC "revocar el acceso ... aparece Volver a entrar ... entrar →
/// vuelve a copiar").
class _SessionRevokedOnceCloudFolder implements CloudFolder {
  _SessionRevokedOnceCloudFolder(this.session);

  final FakeGoogleDriveSession session;
  final CloudFolder _inner = InMemoryCloudFolder();
  bool _revokedOnce = false;

  Future<void> _maybeRevoke() async {
    if (!_revokedOnce) {
      _revokedOnce = true;
      await session.disconnect();
      throw const CloudUnavailable('sin sesión de Google');
    }
    if (!session.isConnected) {
      throw const CloudUnavailable('sin sesión de Google');
    }
  }

  @override
  Future<List<String>> list() async {
    await _maybeRevoke();
    return _inner.list();
  }

  @override
  Future<String?> read(String name) async {
    await _maybeRevoke();
    return _inner.read(name);
  }

  @override
  Future<void> write(String name, String content) async {
    await _maybeRevoke();
    await _inner.write(name, content);
  }
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

  testWidgets(
    'tapping Copiar ahora shows Copiando… during sync, then success',
    (tester) async {
      final cloudFolder = CompleterCloudFolder();
      final pausedOverride = cloudCopyUseCaseProvider.overrideWith(
        (ref) async => buildTestCloudCopyUseCase(cloudFolder: cloudFolder),
      );
      await _pumpScreen(tester, override: pausedOverride);

      await tester.tap(find.byKey(const Key('connectGoogleDriveButton')));
      await tester.pumpAndSettle();

      cloudFolder.pause();
      await tester.tap(find.byKey(const Key('copyNowButton')));
      await tester.pump();

      expect(find.text('Copiando…'), findsOneWidget);

      cloudFolder.resume();
      await tester.pumpAndSettle();

      expect(find.text('Copia en Drive: hace un momento'), findsOneWidget);
    },
  );

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

  testWidgets(
    'a revoked Google session shows "sin sesión de Google" and offers to '
    'reconnect',
    (tester) async {
      final session = FakeGoogleDriveSession();
      final revokedOverride = cloudCopyUseCaseProvider.overrideWith(
        (ref) async => buildTestCloudCopyUseCase(
          cloudFolder: _SessionRevokedOnceCloudFolder(session),
        ),
      );
      await _pumpScreen(tester, override: revokedOverride, session: session);

      await tester.tap(find.byKey(const Key('connectGoogleDriveButton')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Falló hace un momento: sin sesión de Google — tocá para reintentar',
        ),
        findsOneWidget,
      );
      expect(find.text('Conectar mi Google Drive'), findsOneWidget);
      expect(find.text('Desconectar'), findsNothing);

      await tester.tap(find.byKey(const Key('connectGoogleDriveButton')));
      await tester.pumpAndSettle();

      expect(find.text('Copia en Drive: hace un momento'), findsOneWidget);
      expect(find.text('Desconectar'), findsOneWidget);
    },
  );
}
