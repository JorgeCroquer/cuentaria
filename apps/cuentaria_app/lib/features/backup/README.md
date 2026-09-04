# Backup

UI and app-layer wiring for the Backup File and Spreadsheet Export
(ADR-0021): `CreateBackup`/`RestoreBackup` (`application/`) drive the
`package:backup` domain through the system share sheet and file picker;
`BackupScreen` (`ui/`) is the entry point.

## Verifying `android:allowBackup` (ADR-0021 errata, issue #246)

A manifest attribute like `allowBackup="false"` only takes effect once
merged into the compiled APK — checking the source manifest under
`android/app/src/main/AndroidManifest.xml` isn't proof it landed
(manifest merging from plugins/build variants can override it). Verify
against the built binary instead:

```
aapt2 dump xmltree build/app/outputs/apk/release/app-release.apk --file AndroidManifest.xml
```

or for an app bundle:

```
aapt2 dump xmltree build/app/outputs/bundle/release/app-release.aab --file AndroidManifest.xml
```

Look for `A: http://schemas.android.com/apk/res/android:allowBackup(...)=false`
and a `dataExtractionRules` attribute pointing at `@xml/data_extraction_rules`
on the `application` element.
