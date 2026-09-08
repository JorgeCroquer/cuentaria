import 'package:backup/backup.dart';
import 'package:contabilidad/infrastructure/database/cloud_copy_status_store.dart';

import '../../backup/application/create_backup.dart';
import '../../backup/application/restore_backup.dart';
import 'cloud_copy_status.dart';

/// Orchestrates the Cloud Copy (issue #222, ADR-0023 §2): one Backup File
/// per device (`<device_id>.ndjson`) in the user's own [CloudFolder].
/// `push` writes this device's file; `pull` reads every other device's file
/// through the existing [RestoreBackup] (all-or-nothing per file, ADR-0021
/// §6-7 already resolves the merge — duplicates by `event_id`, config by
/// `updatedAt`); `sync` does both when [isConnected].
///
/// No engine, no deltas, no cursors (ADR-0023 §2): the whole file is
/// rewritten every push, and every foreign file is re-read every pull.
class CloudCopyUseCase {
  final CreateBackup createBackup;
  final RestoreBackup restoreBackup;
  final CloudFolder cloudFolder;
  final CloudCopyStatusStore statusStore;
  final String deviceId;
  final Future<bool> Function() isConnected;
  final Future<bool> Function() getMergeConsent;
  final Future<void> Function(bool) setMergeConsent;
  final DateTime Function() _now;

  CloudCopyStatus _status = const CloudCopyStatus();

  CloudCopyUseCase({
    required this.createBackup,
    required this.restoreBackup,
    required this.cloudFolder,
    required this.statusStore,
    required this.deviceId,
    this.isConnected = _alwaysConnected,
    this.getMergeConsent = _neverConsented,
    this.setMergeConsent = _ignoreConsent,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static Future<bool> _alwaysConnected() async => true;
  static Future<bool> _neverConsented() async => false;
  static Future<void> _ignoreConsent(bool _) async {}

  String get _ownFileName => '$deviceId.ndjson';

  /// Current status, as of the last [hydrate] plus any push/pull/sync run
  /// since.
  CloudCopyStatus get status => _status;

  /// Loads the persisted parts of [status] (`lastSuccessAt`, `lastError`)
  /// from [statusStore]. Call once after construction, e.g. after the app's
  /// database is ready — mirrors `CatalogRepository.hydrate`.
  Future<void> hydrate() async {
    _status = CloudCopyStatus(
      lastSuccessAt: await statusStore.getLastSuccessAt(),
      lastError: await statusStore.getLastError(),
    );
  }

  /// Writes this device's Backup File to the cloud folder, byte-identical
  /// to [CreateBackup]'s output. Never throws — failures surface via
  /// [status].
  Future<void> push() async {
    _beginAttempt();
    try {
      final backup = await createBackup.call();
      await cloudFolder.write(_ownFileName, backup.content);
      await _recordSuccess();
    } catch (e) {
      await _recordError(_describe(e));
    }
  }

  /// Restores every other device's Backup File found in the cloud folder.
  /// Each file is all-or-nothing (ADR-0021 §6): a broken file is reported by
  /// name and line and does not block the others. Never throws — failures
  /// surface via [status].
  Future<void> pull() async {
    _beginAttempt();
    try {
      final names = await cloudFolder.list();
      String? failure;
      for (final name in names) {
        if (name == _ownFileName) continue;
        final content = await cloudFolder.read(name);
        if (content == null) continue;
        try {
          await restoreBackup.call(content);
        } on RestoreBackupError catch (e) {
          failure = '$name: ${e.message}';
        }
      }
      if (failure != null) {
        await _recordError(failure);
      } else {
        await _recordSuccess();
      }
    } catch (e) {
      await _recordError(_describe(e));
    }
  }

  /// Whether connecting now would join two independent histories (issue
  /// #226, ADR-0023 §6): this device already has events *and* the cloud
  /// folder already has another device's file. Read-only — never mutates
  /// [status] and never throws; a failed check (e.g. offline) reports no
  /// pending merge, since [sync] will surface the same failure via [status].
  Future<bool> hasPendingMerge() async {
    try {
      final localEvents = (await createBackup.call()).counts.event;
      if (localEvents == 0) return false;
      final names = await cloudFolder.list();
      return names.any((name) => name != _ownFileName);
    } catch (_) {
      return false;
    }
  }

  Future<void>? _activeSync;
  bool _syncQueued = false;

  /// Pulls then pushes when [isConnected]. Overlapping calls never run in
  /// parallel: a call arriving while one is in flight waits for it and then
  /// runs once more; a third call arriving while one is already queued is
  /// discarded (piggybacks on the queued run instead of starting a new one).
  Future<void> sync() {
    if (_activeSync != null) {
      if (_syncQueued) return _activeSync!;
      _syncQueued = true;
      final queued = _activeSync!.then((_) {
        _syncQueued = false;
        return sync();
      });
      return queued;
    }

    final run = _runSync();
    _activeSync = run;
    run.whenComplete(() => _activeSync = null);
    return run;
  }

  /// The merge gate (issue #297, ADR-0023 §6) lives here, not in the screen:
  /// every caller of `sync` — the screen, `CloudCopyTriggers` on resume, the
  /// debounced post-Transaction trigger — shares this one check, so none of
  /// them can race a still-open merge dialog into pulling foreign history.
  /// Once a run gets past the gate (whether because there was nothing to
  /// merge, or because [getMergeConsent] said yes), it marks this device
  /// consented for good: a device that never collided on its first sync must
  /// not get gated later just because its own data grew into a collision
  /// (e.g. it recorded a movement after merging in another device's file).
  Future<void> _runSync() async {
    if (!await isConnected()) return;
    final consented = await getMergeConsent();
    if (!consented && await hasPendingMerge()) {
      _status = _status.copyWith(waitingForMergeConsent: true);
      return;
    }
    await pull();
    await push();
    if (!consented) await setMergeConsent(true);
  }

  void _beginAttempt() {
    _status = _status.copyWith(lastAttemptAt: _now().toUtc(), inProgress: true);
  }

  Future<void> _recordSuccess() async {
    final now = _now().toUtc();
    await statusStore.setLastSuccessAt(now);
    await statusStore.clearLastError();
    _status = CloudCopyStatus(
      lastSuccessAt: now,
      lastAttemptAt: _status.lastAttemptAt,
      inProgress: false,
    );
  }

  Future<void> _recordError(String message) async {
    await statusStore.setLastError(message);
    _status = _status.copyWith(lastError: message, inProgress: false);
  }

  static String _describe(Object error) => switch (error) {
    CloudUnavailable e => e.reason,
    RestoreBackupError e => e.message,
    _ => error.toString(),
  };
}
