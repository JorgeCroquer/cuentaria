import 'package:backup/domain/ports/cloud_folder.dart';
import 'package:contabilidad/infrastructure/database/cloud_copy_status_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/composition_root.dart';
import '../../backup/application/backup_providers.dart';
import '../infrastructure/google_drive_cloud_folder.dart';
import '../infrastructure/google_sign_in_drive_session.dart';
import 'cloud_copy_use_case.dart';
import 'cloud_session_notifier.dart';
import 'google_drive_session.dart';

/// The user's real Google account session (issue #225, ADR-0023 §8), scope
/// `drive.appdata` only.
final googleDriveSessionProvider = Provider<GoogleDriveSession>(
  (ref) => GoogleSignInDriveSession(),
);

/// The user's Google Drive app folder (issue #225, ADR-0023 §8): every read
/// and write goes through [googleDriveSessionProvider]'s bearer token.
final cloudFolderProvider = Provider<CloudFolder>(
  (ref) => GoogleDriveCloudFolder(ref.watch(googleDriveSessionProvider)),
);

/// Orchestrates this device's Cloud Copy, `isConnected` reading
/// [cloudSessionProvider] (issue #225: the real Google Drive session).
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
