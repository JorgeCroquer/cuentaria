import 'package:backup/domain/ports/cloud_folder.dart';
import 'package:contabilidad/infrastructure/database/cloud_copy_status_store.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/composition_root.dart';
import '../../backup/application/backup_providers.dart';
import '../infrastructure/google_drive_cloud_folder.dart';
import '../infrastructure/google_sign_in_drive_session.dart';
import 'cloud_copy_triggers.dart';
import 'cloud_copy_use_case.dart';
import 'cloud_session_notifier.dart';
import 'cloud_sync_status_notifier.dart';
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

/// Debounce [CloudCopyTriggers] waits after a burst of Transaction events
/// before syncing — overridden to [Duration.zero] in tests so a published
/// Transaction doesn't need a real 30s wait.
final cloudCopyDebounceProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 30),
);

/// Fires [CloudCopyUseCase.sync] on app launch, on every foreground resume,
/// and after each burst of Transaction events (issue #239, ADR-0023 §4) —
/// same lifecycle pattern as `rateSyncTriggerProvider`
/// (`lib/providers/rate_sync_providers.dart`). `sync` goes through
/// [cloudSyncStatusProvider] so the Cloud Copy label stays current without
/// the screen being open.
final cloudCopyTriggersProvider = Provider<AppLifecycleListener>((ref) {
  Future<void> sync() => ref.read(cloudSyncStatusProvider.notifier).sync();

  final triggers = CloudCopyTriggers(
    sync: sync,
    eventBus: ref.watch(eventBusProvider),
    debounce: ref.watch(cloudCopyDebounceProvider),
  );
  final listener = AppLifecycleListener(onResume: triggers.onResume);
  ref.onDispose(() {
    listener.dispose();
    triggers.dispose();
  });
  // Deferred: `sync` writes to cloudSyncStatusProvider, and Riverpod
  // forbids a provider mutating another one while it's still building.
  Future.microtask(triggers.start);
  return listener;
});
