import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The simulated Google Drive session (issue #223): connect/disconnect are
/// in-memory only, mirroring the real flow before the Drive adapter (F3.4)
/// replaces this screen's plumbing without touching the screen itself.
class CloudSession {
  const CloudSession({this.isConnected = false, this.accountName});

  final bool isConnected;
  final String? accountName;
}

/// Owns [CloudSession]. Disconnecting only closes the session — it never
/// deletes local or remote data (ADR-0023 §5).
class CloudSessionNotifier extends Notifier<CloudSession> {
  @override
  CloudSession build() => const CloudSession();

  void connect() {
    state = const CloudSession(
      isConnected: true,
      accountName: 'cuenta de prueba',
    );
  }

  void disconnect() {
    state = const CloudSession();
  }
}

final cloudSessionProvider =
    NotifierProvider<CloudSessionNotifier, CloudSession>(
      CloudSessionNotifier.new,
    );
