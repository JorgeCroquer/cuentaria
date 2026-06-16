/// Drift-backed implementation of [CatalogRepository].
///
/// Architecture (F2-10):
///   - **Reads** (`getAccount` / `getEnvelope` / `getSystemEnvelope`) are
///     served synchronously from an in-memory cache, keeping the sync port
///     intact and C1 factories unchanged.
///   - **Writes** (`saveAccount` / `saveEnvelope` / `deleteEnvelope`) persist
///     to Drift with LWW conflict resolution, then update the cache.
///   - **Boot**: call [hydrate] once after opening the database; it loads all
///     rows into the cache and resolves the role→id index for system envelopes.
///   - **System envelopes** are seeded by [CuentariaDatabase.onCreate] with
///     stable well-known IDs.  [deleteEnvelope] refuses to delete them.
library;

import 'dart:convert';

import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/application/catalog/exceptions.dart';
import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/infrastructure/database/cuentaria_database.dart';
import 'package:drift/drift.dart';
import 'package:shared_kernel/shared_kernel.dart';

class DriftCatalogRepository implements CatalogRepository {
  final CuentariaDatabase _db;

  // In-memory cache — hydrated at boot, kept in sync on every write.
  final Map<AccountId, Account> _accounts = {};
  final Map<EnvelopeId, Envelope> _envelopes = {};
  final Map<EnvelopeRole, EnvelopeId> _systemIndex = {};

  DriftCatalogRepository(this._db);

  // ---------------------------------------------------------------------------
  // Boot: hydrate cache from Drift
  // ---------------------------------------------------------------------------

  /// Loads all rows from Drift into the in-memory cache.
  /// Must be awaited once after the database is opened before any read.
  Future<void> hydrate() async {
    _accounts.clear();
    _envelopes.clear();
    _systemIndex.clear();

    final accountRows = await _db.select(_db.accounts).get();
    for (final row in accountRows) {
      final acc = _accountFromRow(row);
      _accounts[acc.id] = acc;
    }

    final envelopeRows = await _db.select(_db.envelopes).get();
    for (final row in envelopeRows) {
      final env = _envelopeFromRow(row);
      _envelopes[env.id] = env;
      if (env.role != EnvelopeRole.none) {
        _systemIndex[env.role] = env.id;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Reads — synchronous from cache
  // ---------------------------------------------------------------------------

  @override
  Iterable<AccountId> get accountIds => _accounts.keys;

  @override
  Account? getAccount(AccountId id) => _accounts[id];

  @override
  Envelope? getEnvelope(EnvelopeId id) => _envelopes[id];

  @override
  EnvelopeId getSystemEnvelope(EnvelopeRole role) {
    if (role == EnvelopeRole.none) {
      throw ArgumentError('Role none is not a system envelope');
    }
    final id = _systemIndex[role];
    if (id == null) {
      throw TargetNotFound('System envelope for role $role not found');
    }
    return id;
  }

  // ---------------------------------------------------------------------------
  // Writes — persist to Drift + update cache (LWW)
  // ---------------------------------------------------------------------------

  @override
  Future<void> saveAccount(Account account) async {
    final existing = _accounts[account.id];
    final merged = existing != null ? existing.mergeWith(account) : account;

    await _db
        .into(_db.accounts)
        .insertOnConflictUpdate(_accountToCompanion(merged));
    _accounts[account.id] = merged;
  }

  @override
  Future<void> saveEnvelope(Envelope envelope) async {
    final existing = _envelopes[envelope.id];
    final merged = existing != null ? existing.mergeWith(envelope) : envelope;

    await _db
        .into(_db.envelopes)
        .insertOnConflictUpdate(_envelopeToCompanion(merged));
    _envelopes[envelope.id] = merged;
    if (merged.role != EnvelopeRole.none) {
      _systemIndex[merged.role] = merged.id;
    }
  }

  @override
  Future<void> deleteEnvelope(EnvelopeId id) async {
    final envelope = _envelopes[id];
    if (envelope != null && envelope.role != EnvelopeRole.none) {
      throw SystemEnvelopeDeletionNotAllowed(
        'Cannot delete system envelope ${envelope.role.name}',
      );
    }
    await (_db.delete(_db.envelopes)..where((t) => t.id.equals(id.value))).go();
    _envelopes.remove(id);
  }

  // ---------------------------------------------------------------------------
  // Mappers
  // ---------------------------------------------------------------------------

  Account _accountFromRow(AccountRow row) => Account(
    id: AccountId(row.id),
    name: row.name,
    nativeCurrency: CurrencyCode(row.nativeCurrency),
    provider: row.provider,
    isArchived: row.isArchived,
    updatedAt: DateTime.fromMicrosecondsSinceEpoch(row.updatedAt, isUtc: true),
  );

  AccountsCompanion _accountToCompanion(Account a) => AccountsCompanion(
    id: Value(a.id.value),
    name: Value(a.name),
    nativeCurrency: Value(a.nativeCurrency.value),
    provider: Value(a.provider),
    isArchived: Value(a.isArchived),
    updatedAt: Value(a.updatedAt.microsecondsSinceEpoch),
  );

  Envelope _envelopeFromRow(EnvelopeRow row) {
    final role = EnvelopeRole.values.firstWhere(
      (r) => r.name == row.role,
      orElse: () => EnvelopeRole.none,
    );
    final meta =
        (row.meta != null && row.meta!.isNotEmpty)
            ? (jsonDecode(row.meta!) as Map<String, dynamic>)
            : null;
    return Envelope(
      id: EnvelopeId(row.id),
      name: row.name,
      role: role,
      isArchived: row.isArchived,
      updatedAt: DateTime.fromMicrosecondsSinceEpoch(
        row.updatedAt,
        isUtc: true,
      ),
      meta: meta,
    );
  }

  EnvelopesCompanion _envelopeToCompanion(Envelope e) => EnvelopesCompanion(
    id: Value(e.id.value),
    name: Value(e.name),
    role: Value(e.role.name),
    isArchived: Value(e.isArchived),
    updatedAt: Value(e.updatedAt.microsecondsSinceEpoch),
    meta: Value(e.meta != null ? jsonEncode(e.meta) : null),
  );
}
