/// The Google account session behind Cloud Copy (issue #225, ADR-0023 §8):
/// scope **only** `drive.appdata`, so Drive never sees more than the app's
/// own hidden folder. [GoogleDriveCloudFolder] and [CloudSessionNotifier]
/// share this one port — the real [GoogleSignInDriveSession] backs the app,
/// a fake backs tests, mirroring [SystemShare]/[SystemFilePicker].
abstract class GoogleDriveSession {
  /// Whether a Google account is currently signed in.
  bool get isConnected;

  /// The signed-in account's email, or null when [isConnected] is false.
  String? get accountEmail;

  /// Opens the account picker and signs in. A user-cancelled picker leaves
  /// the session disconnected without throwing.
  Future<void> connect();

  /// Signs out locally — never touches local or remote data (ADR-0023 §5).
  Future<void> disconnect();

  /// Clears any client-side cache of the current account's token. After a
  /// 401 from Drive, callers must call this before requesting a fresh
  /// [accessToken] — otherwise the cache keeps serving the same stale token
  /// (issue #236).
  Future<void> clearAuthCache();

  /// A bearer token for the Drive API, or throws
  /// `CloudUnavailable('sin sesión de Google')` when [isConnected] is false
  /// or the session cannot be refreshed.
  Future<String> accessToken();
}
