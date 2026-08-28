import 'package:backup/infrastructure/in_memory_cloud_folder.dart';
import 'package:cuentaria_app/features/cloud_copy/application/cloud_copy_providers.dart';
import 'package:cuentaria_app/features/cloud_copy/application/cloud_session_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cloud_copy_test_support.dart';

void main() {
  setUpAll(ensureSqlite3ForTests);

  ProviderContainer buildContainer(FakeGoogleDriveSession session) {
    final container = ProviderContainer(
      overrides: [
        googleDriveSessionProvider.overrideWithValue(session),
        cloudCopyUseCaseProvider.overrideWith(
          (ref) async =>
              buildTestCloudCopyUseCase(cloudFolder: InMemoryCloudFolder()),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('initial state is disconnected', () {
    final container = buildContainer(FakeGoogleDriveSession());

    final session = container.read(cloudSessionProvider);

    expect(session.isConnected, isFalse);
    expect(session.accountName, isNull);
  });

  test(
    'connect() marks the session connected with the signed-in account',
    () async {
      final container = buildContainer(FakeGoogleDriveSession());

      await container.read(cloudSessionProvider.notifier).connect();

      final session = container.read(cloudSessionProvider);
      expect(session.isConnected, isTrue);
      expect(session.accountName, equals('cuenta de prueba'));
    },
  );

  test('disconnect() clears the session', () async {
    final container = buildContainer(FakeGoogleDriveSession());
    await container.read(cloudSessionProvider.notifier).connect();

    await container.read(cloudSessionProvider.notifier).disconnect();

    final session = container.read(cloudSessionProvider);
    expect(session.isConnected, isFalse);
    expect(session.accountName, isNull);
  });

  test('refresh() re-reads the session without calling connect/disconnect', () {
    final driveSession = FakeGoogleDriveSession('already-connected');
    final container = buildContainer(driveSession);

    container.read(cloudSessionProvider.notifier).refresh();

    final session = container.read(cloudSessionProvider);
    expect(session.isConnected, isTrue);
    expect(session.accountName, equals('cuenta de prueba'));
  });
}
