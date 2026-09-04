import 'package:backup/domain/ports/cloud_folder.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../application/google_drive_session.dart';

/// Scope requested from Google (issue #225): only the app's own hidden
/// folder, never the user's visible Drive files.
const driveAppDataScope = 'https://www.googleapis.com/auth/drive.appdata';

/// [GoogleDriveSession] backed by the real `google_sign_in` plugin. On
/// Android the OAuth client is resolved from the app's package name and
/// signing SHA-1 (registered in Google Cloud, see the feature README) — no
/// client ID needed in code.
class GoogleSignInDriveSession implements GoogleDriveSession {
  GoogleSignInDriveSession({GoogleSignIn? googleSignIn})
    : _googleSignIn = googleSignIn ?? GoogleSignIn(scopes: [driveAppDataScope]);

  final GoogleSignIn _googleSignIn;

  @override
  bool get isConnected => _googleSignIn.currentUser != null;

  @override
  String? get accountEmail => _googleSignIn.currentUser?.email;

  @override
  Future<void> connect() async {
    await _googleSignIn.signIn();
  }

  @override
  Future<void> disconnect() async {
    try {
      await _googleSignIn.disconnect();
    } catch (_) {
      await _googleSignIn.signOut();
    }
  }

  @override
  Future<void> clearAuthCache() async {
    await _googleSignIn.currentUser?.clearAuthCache();
  }

  @override
  Future<String> accessToken() async {
    final account = _googleSignIn.currentUser;
    if (account == null) {
      throw const CloudUnavailable('sin sesión de Google');
    }
    final token = (await account.authentication).accessToken;
    if (token == null) {
      throw const CloudUnavailable('sin sesión de Google');
    }
    return token;
  }
}
