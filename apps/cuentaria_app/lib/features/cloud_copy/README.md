# Cloud Copy

Orchestrates `CloudCopyUseCase.sync()` (issue #222, ADR-0023): push this
device's Backup File, pull every other device's, both through the existing
`CreateBackup`/`RestoreBackup` (`application/cloud_copy_use_case.dart`).

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
