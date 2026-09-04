# Cloud Copy

Orchestrates `CloudCopyUseCase.sync()` (issue #222, ADR-0023): push this
device's Backup File, pull every other device's, both through the existing
`CreateBackup`/`RestoreBackup` (`application/cloud_copy_use_case.dart`).

## Google Drive adapter (issue #225, ADR-0023 §8)

`GoogleDriveCloudFolder` (`infrastructure/google_drive_cloud_folder.dart`)
implements the `CloudFolder` port from `package:backup` over Drive API v3's
`appDataFolder` — a hidden per-app folder, invisible in the user's normal
Drive. `GoogleSignInDriveSession` (`infrastructure/google_sign_in_drive_session.dart`)
wraps `google_sign_in` with scope **only** `drive.appdata`; both talk to
each other through the `GoogleDriveSession` port
(`application/google_drive_session.dart`) so tests can swap in a fake
(`FakeGoogleDriveSession` in `test/features/cloud_copy/cloud_copy_test_support.dart`)
without touching a real Google account.

`CloudSessionNotifier` reads/writes `GoogleDriveSession` and mirrors it into
`CloudSession` for the screen — `connect()`/`disconnect()` await the real
session and refresh; `connect()` also kicks the first `sync()` once the
account picker actually resolves, since the screen's own post-`connect()`
`sync()` call races ahead of that interactive step. `CloudSyncStatusNotifier`
refreshes the session again after every `sync()`, because a revoked Google
session surfaces mid-sync: `GoogleDriveCloudFolder` disconnects the session
itself on an HTTP 401 and throws `CloudUnavailable('sin sesión de Google')`,
so the account button flips back to "Conectar mi Google Drive" for the user
to reconnect. A network failure throws `CloudUnavailable('sin internet')`.

### HITL setup (done 2026-08-27)

Google Cloud project `cuentaria`, Drive API enabled, OAuth consent screen in
**Testing** mode with scope `drive.appdata`. Android OAuth client (public,
not a secret — see `android/app/src/main/res/values/strings.xml`):
`717754217213-48bt8ffelrm1gqhoi0iu92a2fbmdtfip.apps.googleusercontent.com`,
package `com.example.cuentaria_app`, SHA-1 `9E:01:78:80:97:80:17:B0:F1:99:07:C7:E8:F4:6E:4D:2A:32:B7:A9`
(`~/.android/debug.keystore`; release also signs with the debug key, see
`android/app/build.gradle.kts`). On Android, `google_sign_in` resolves the
OAuth client from package name + SHA-1 — no client ID needed in Dart code.

### Correr el contract test contra Drive real

`test/features/cloud_copy/google_drive_cloud_folder_contract_test.dart` runs
the shared `cloudFolderContractTests` (from `package:backup`) against a real
`GoogleDriveCloudFolder`. It's tagged `google_drive` and skipped by default
(`dart_test.yaml`) — CI never touches a real Drive account. To run it by
hand (off-sandbox: needs internet and a signed-in Google account):

1. Get a fresh access token scoped to `drive.appdata`. Easiest: run the app
   on a device, connect Google Drive from the Cloud Copy screen, then
   temporarily log `await googleDriveSessionProvider`'s session
   `.accessToken()` (e.g. from a debugger or a one-off `print`) and copy it.
   Tokens expire in about an hour, so get one right before running the test.
2. From `apps/cuentaria_app`:
   ```
   flutter test --tags google_drive --run-skipped \
     --dart-define=GOOGLE_DRIVE_TEST_TOKEN=<token> \
     test/features/cloud_copy/google_drive_cloud_folder_contract_test.dart
   ```
3. Every write it makes lands (and stays) in `appDataFolder` — check via
   Drive web → Ajustes → Gestionar aplicaciones → Cuentaria to confirm the
   data is there and hidden from the normal Drive folder view.

## Automatic triggers (issue #224, ADR-0023 §4)

`CloudCopyTriggers` (`application/cloud_copy_triggers.dart`) decides *when*
to call `sync()`; it never re-implements what `sync()` already owns
(overlap dedup, the `isConnected` check):

- **App launch and every return to foreground** — `start()` fires once
  immediately; `onResume()` (wired to the app's lifecycle listener) fires
  again on every resume.
- **After a Transaction** — each `Transaction` published on the in-process
  `EventBus` restarts a short debounce; a burst of movements produces one
  `sync()` call, not one per movement.
- **Non-blocking** — the event-bus callback never awaits `sync()`, so a
  slow or unreachable cloud folder never delays recording a movement.

## What this does not do

**The app must be open for the Cloud Copy to run.** There is no background
scheduler, no OS-level periodic task, and no push mechanism: closing the
app (or the phone staying locked/killed) means no push and no pull until
it's opened again. This is intentional (ADR-0023 §4/§8) — the same
"graceful degradation, no backoff, no system wake" the ADR asks for. A
disconnected or unavailable cloud simply leaves the last error in
`CloudCopyStatus`; the next trigger retries on its own.
