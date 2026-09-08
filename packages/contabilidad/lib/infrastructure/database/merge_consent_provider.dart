/// Persists whether this device has been cleared to sync with the cloud
/// folder even though doing so would join two independent histories (issue
/// #297, ADR-0023 §6): the merge gate lives in `CloudCopyUseCase.sync()`, so
/// its decision has to survive across every caller of `sync()` — the screen,
/// `CloudCopyTriggers` on resume, the debounced post-Transaction trigger —
/// and across app restarts, not just live in the screen's own state (that
/// was the bug: a resume firing `sync()` while the dialog was still up).
///
/// Stored in the local-only [AppMeta] table (`key = 'merge_consented'`), the
/// same key/value table [DeviceIdProvider] and [LastBackupProvider] use.
/// Never synced: it's this install's decision, not a fact of the user's
/// finances.
library;

import 'cuentaria_database.dart';

class MergeConsentProvider {
  static const _mergeConsentedKey = 'merge_consented';

  final CuentariaDatabase _db;

  MergeConsentProvider(this._db);

  /// Whether this device is cleared to sync past the merge gate — false
  /// until [setConsent] is called with `true`.
  Future<bool> hasConsent() async {
    final row =
        await (_db.select(_db.appMeta)
          ..where((t) => t.key.equals(_mergeConsentedKey))).getSingleOrNull();
    return row?.value == 'true';
  }

  /// Persists [value] as the new consent flag, replacing any prior one.
  Future<void> setConsent(bool value) async {
    await _db
        .into(_db.appMeta)
        .insertOnConflictUpdate(
          AppMetaCompanion.insert(
            key: _mergeConsentedKey,
            value: value.toString(),
          ),
        );
  }
}
