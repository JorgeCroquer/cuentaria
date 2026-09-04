import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cloud_copy_providers.dart';

/// The Google Drive session (issue #225, ADR-0023 §5): mirrors
/// [GoogleDriveSession]'s `isConnected`/`accountEmail`.
class CloudSession {
  const CloudSession({this.isConnected = false, this.accountName});

  final bool isConnected;
  final String? accountName;
}

/// Owns [CloudSession], read from [googleDriveSessionProvider]. Disconnecting
/// only closes the session — it never deletes local or remote data
/// (ADR-0023 §5).
class CloudSessionNotifier extends Notifier<CloudSession> {
  @override
  CloudSession build() => _fromSession();

  CloudSession _fromSession() {
    final session = ref.read(googleDriveSessionProvider);
    return session.isConnected
        ? CloudSession(isConnected: true, accountName: session.accountEmail)
        : const CloudSession();
  }

  /// Re-reads the session — call after anything that might have changed it
  /// without going through [connect]/[disconnect], e.g. a sync that hit a
  /// revoked Google session ([GoogleDriveCloudFolder] disconnects it on a
  /// 401).
  void refresh() {
    state = _fromSession();
  }

  /// Opens the Google account picker and waits for it to settle — a
  /// user-cancelled picker leaves the session disconnected. Only connects;
  /// callers decide whether and how to sync (issue #241: this notifier used
  /// to fire the first sync itself, which raced ahead of the screen's own
  /// merge-warning check and could merge silently).
  Future<void> connect() async {
    await ref.read(googleDriveSessionProvider).connect();
    refresh();
  }

  Future<void> disconnect() async {
    await ref.read(googleDriveSessionProvider).disconnect();
    refresh();
  }
}

final cloudSessionProvider =
    NotifierProvider<CloudSessionNotifier, CloudSession>(
      CloudSessionNotifier.new,
    );
