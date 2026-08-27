import 'package:backup/infrastructure/in_memory_cloud_folder.dart';
import 'package:cuentaria_app/features/cloud_copy/application/cloud_copy_providers.dart';
import 'package:cuentaria_app/features/cloud_copy/application/cloud_sync_status_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cloud_copy_test_support.dart';

void main() {
  setUpAll(ensureSqlite3ForTests);

  test('initial state is idle', () {
    final container = ProviderContainer(
      overrides: [
        cloudCopyUseCaseProvider.overrideWith(
          (ref) async =>
              buildTestCloudCopyUseCase(cloudFolder: InMemoryCloudFolder()),
        ),
      ],
    );
    addTearDown(container.dispose);

    final status = container.read(cloudSyncStatusProvider);

    expect(status.inProgress, isFalse);
    expect(status.lastSuccessAt, isNull);
    expect(status.lastError, isNull);
  });

  test('sync() goes in-progress, then success with lastSuccessAt', () async {
    final container = ProviderContainer(
      overrides: [
        cloudCopyUseCaseProvider.overrideWith(
          (ref) async =>
              buildTestCloudCopyUseCase(cloudFolder: InMemoryCloudFolder()),
        ),
      ],
    );
    addTearDown(container.dispose);

    final future = container.read(cloudSyncStatusProvider.notifier).sync();
    expect(container.read(cloudSyncStatusProvider).inProgress, isTrue);

    await future;

    final status = container.read(cloudSyncStatusProvider);
    expect(status.inProgress, isFalse);
    expect(status.lastSuccessAt, isNotNull);
  });

  test('a CloudUnavailable failure surfaces as lastError', () async {
    final container = ProviderContainer(
      overrides: [
        cloudCopyUseCaseProvider.overrideWith(
          (ref) async => buildTestCloudCopyUseCase(
            cloudFolder: const FailingCloudFolder('sin internet'),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(cloudSyncStatusProvider.notifier).sync();

    final status = container.read(cloudSyncStatusProvider);
    expect(status.lastError, equals('sin internet'));
    expect(status.inProgress, isFalse);
  });

  test('retry() calls sync() again', () async {
    final container = ProviderContainer(
      overrides: [
        cloudCopyUseCaseProvider.overrideWith(
          (ref) async => buildTestCloudCopyUseCase(
            cloudFolder: const FailingCloudFolder('sin internet'),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(cloudSyncStatusProvider.notifier);
    await notifier.sync();
    expect(container.read(cloudSyncStatusProvider).lastError, isNotNull);

    await notifier.retry();

    expect(container.read(cloudSyncStatusProvider).lastError, isNotNull);
  });

  test('reset() clears state back to idle', () async {
    final container = ProviderContainer(
      overrides: [
        cloudCopyUseCaseProvider.overrideWith(
          (ref) async =>
              buildTestCloudCopyUseCase(cloudFolder: InMemoryCloudFolder()),
        ),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(cloudSyncStatusProvider.notifier);
    await notifier.sync();
    expect(container.read(cloudSyncStatusProvider).lastSuccessAt, isNotNull);

    notifier.reset();

    final status = container.read(cloudSyncStatusProvider);
    expect(status.lastSuccessAt, isNull);
    expect(status.lastError, isNull);
    expect(status.inProgress, isFalse);
  });
}
