import 'package:backup/domain/ports/cloud_folder.dart';
import 'package:backup/infrastructure/in_memory_cloud_folder.dart';
import 'package:contabilidad/infrastructure/database/cloud_copy_status_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/composition_root.dart';
import '../../backup/application/backup_providers.dart';
import 'cloud_copy_use_case.dart';
import 'cloud_session_notifier.dart';

/// The user's Google Drive app folder (issue #223, ADR-0023 §8):
/// [InMemoryCloudFolder] stands in until the real Drive adapter (F3.4)
/// replaces this single provider — the screen and notifiers never change.
final cloudFolderProvider = Provider<CloudFolder>(
  (ref) => InMemoryCloudFolder(),
);

/// Orchestrates this device's Cloud Copy, `isConnected` reading the
/// simulated [cloudSessionProvider] session (issue #223).
final cloudCopyUseCaseProvider = FutureProvider<CloudCopyUseCase>((ref) async {
  final createBackup = await ref.watch(createBackupProvider.future);
  final restoreBackup = await ref.watch(restoreBackupProvider.future);
  final cloudFolder = ref.watch(cloudFolderProvider);
  final db = await ref.watch(databaseProvider.future);
  final deviceId = await ref.watch(deviceIdProvider.future);
  return CloudCopyUseCase(
    createBackup: createBackup,
    restoreBackup: restoreBackup,
    cloudFolder: cloudFolder,
    statusStore: CloudCopyStatusStore(db),
    deviceId: deviceId,
    isConnected: () async => ref.read(cloudSessionProvider).isConnected,
  );
});
