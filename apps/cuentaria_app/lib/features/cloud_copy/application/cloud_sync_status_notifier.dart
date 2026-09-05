import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cloud_copy_providers.dart';
import 'cloud_copy_status.dart';
import 'cloud_session_notifier.dart';

/// Drives [CloudCopyStatus] for the Cloud Copy screen (issue #223): sets
/// `inProgress` immediately so "Copiando…" shows without waiting on the
/// use case itself, then adopts its status once the run (push+pull)
/// settles.
class CloudSyncStatusNotifier extends Notifier<CloudCopyStatus> {
  @override
  CloudCopyStatus build() => const CloudCopyStatus();

  Future<void> sync() async {
    state = state.copyWith(inProgress: true);
    final useCase = await ref.read(cloudCopyUseCaseProvider.future);
    await useCase.sync();
    state = useCase.status;
    // A revoked Google session (issue #225) disconnects itself mid-sync
    // (GoogleDriveCloudFolder, on a 401) — reflect that in the account
    // button so it offers to reconnect.
    ref.read(cloudSessionProvider.notifier).refresh();
  }

  /// Retries after a failure — same as [sync], named for the "toca para
  /// reintentar" affordance.
  Future<void> retry() => sync();

  /// Clears the label back to idle, e.g. after the session disconnects
  /// (ADR-0023 §5: "limpia la etiqueta").
  void reset() {
    state = const CloudCopyStatus();
  }
}

final cloudSyncStatusProvider =
    NotifierProvider<CloudSyncStatusNotifier, CloudCopyStatus>(
      CloudSyncStatusNotifier.new,
    );
