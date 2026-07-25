/// Drift database definition for Cuentaria — schema v3.
///
/// Two version counters (F2-8):
///   - [schemaVersion] (= 3): Drift structural schema version → controls
///     `MigrationStrategy` and table DDL.
///   - `schema_version` column inside `events.payload`: event-shape version,
///     used by [EventCodec] upcaster registry. Starts at 1 (identity upcast).
///
/// Tables:
///   - [Events]: canonical event log (append-only).
///   - [EventTargets]: derived index rows for account/envelope queries.
///   - [Accounts]: catalog — LWW config, survives reopen.
///   - [Envelopes]: catalog — LWW config with stable system-envelope IDs.
///   - [CascadeConfig]: single-row cascade plan — LWW config (C2, ADR-0015).
///   - [AppMeta]: local-only device metadata, never synced (slice #45).
///
/// [QueryExecutor] is injected so that tests can use [NativeDatabase.memory()]
/// and production can swap in an SQLCipher executor (slice #45).
library;

import 'package:drift/drift.dart';

part 'cuentaria_database.g.dart';

// ---------------------------------------------------------------------------
// Table: events
// ---------------------------------------------------------------------------

/// Append-only event log — the single source of truth.
///
/// Column notes:
///   - [eventId]: UUID text PK; uniqueness enforced by SQLite PK constraint.
///   - [occurredAt] / [recordedAt]: epoch microseconds for integer-comparison
///     ordering (canonical order: occurred_at → recorded_at → event_id).
///   - [schemaVersion]: event-shape version (NOT the Drift schema version).
///   - [reverses]: nullable UUID of the event this one reverses.
///   - [payload]: canonical JSON from [EventCodec]. This is the truth; columns
///     above are extracted for indexing only.
class Events extends Table {
  TextColumn get eventId => text()();
  TextColumn get type => text()();
  IntColumn get occurredAt => integer()();
  IntColumn get recordedAt => integer()();
  IntColumn get schemaVersion => integer()();
  TextColumn get reverses => text().nullable()();
  TextColumn get payload => text()();

  @override
  Set<Column> get primaryKey => {eventId};
}

// ---------------------------------------------------------------------------
// Table: event_targets
// ---------------------------------------------------------------------------

/// Derived index: one row per distinct (account|envelope) target in an event.
///
/// Not a source of truth — derived from [payload] at insert time. Used to
/// filter [queryLog] by account or envelope without parsing JSON.
///
/// [dimension] values: `'account'` | `'envelope'` (mirrors [Dimension] enum).
@DataClassName('EventTarget')
class EventTargets extends Table {
  TextColumn get eventId => text()();
  TextColumn get dimension => text()();
  TextColumn get targetId => text()();
}

// ---------------------------------------------------------------------------
// Table: accounts  (LWW catalog)
// ---------------------------------------------------------------------------

/// Durable catalog of Accounts.  LWW merge is done in [DriftCatalogRepository]
/// by comparing [updatedAt] epoch-microseconds before writing.
@DataClassName('AccountRow')
class Accounts extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get nativeCurrency => text()();
  TextColumn get provider => text().nullable()();
  BoolColumn get isArchived => boolean()();
  IntColumn get updatedAt => integer()(); // epoch µs
  TextColumn get meta => text().nullable()(); // JSON

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Table: envelopes  (LWW catalog)
// ---------------------------------------------------------------------------

/// Durable catalog of Envelopes, including the four system envelopes seeded in
/// [onCreate].  [role] is stored here only as the initial seed; [role] is
/// immutable and enforced by [DriftCatalogRepository] during LWW merge.
@DataClassName('EnvelopeRow')
class Envelopes extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get role => text()(); // EnvelopeRole.name
  BoolColumn get isArchived => boolean()();
  IntColumn get updatedAt => integer()(); // epoch µs
  TextColumn get meta => text().nullable()(); // JSON

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Table: cascade_config  (single-row LWW config, C2 ADR-0015)
// ---------------------------------------------------------------------------

/// Single-row table holding the serialized cascade plan.
///
/// [rowId] is always 'singleton' — only one row ever exists.
/// [steps] is a JSON array of [CascadeStep] objects.
/// [updatedAt] is epoch microseconds for LWW conflict resolution.
@DataClassName('CascadeConfigRow')
class CascadeConfig extends Table {
  TextColumn get rowId => text()();
  TextColumn get steps => text()(); // JSON array
  IntColumn get updatedAt => integer()(); // epoch µs

  @override
  Set<Column> get primaryKey => {rowId};
}

// ---------------------------------------------------------------------------
// Table: app_meta  (local-only, never synced)
// ---------------------------------------------------------------------------

/// Local-only device metadata (e.g. `device_id`, slice #45).
///
/// Never synced: it identifies *this install*, not a domain fact. Sync logic
/// (when it lands) must exclude this table explicitly.
@DataClassName('AppMetaRow')
class AppMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------

@DriftDatabase(
  tables: [Events, EventTargets, Accounts, Envelopes, CascadeConfig, AppMeta],
)
class CuentariaDatabase extends _$CuentariaDatabase {
  CuentariaDatabase(super.e);

  /// Drift structural schema version. Increment when tables change.
  /// See also [schemaVersion] column in [events] (different counter — F2-8).
  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      // Composite index: canonical ordering + covering for full-log scan.
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_events_order '
        'ON events (occurred_at, recorded_at, event_id)',
      );
      // Indexes on event_targets for fast filter queries.
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_event_targets_target '
        'ON event_targets (target_id)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_event_targets_event '
        'ON event_targets (event_id)',
      );
      await _seedSystemEnvelopes();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(cascadeConfig);
      }
      if (from < 3) {
        await m.createTable(appMeta);
      }
      if (from < 4) {
        await m.addColumn(accounts, accounts.meta);
      }
    },
  );

  /// Seeds the four system envelopes with stable well-known IDs (F2-9-c).
  /// Uses INSERT OR IGNORE so re-running is idempotent.
  Future<void> _seedSystemEnvelopes() async {
    const epoch0 = 0; // oldest possible updatedAt — any real write wins LWW
    const seeds = [
      ('sys-stage', 'Stage', 'stage'),
      ('sys-differential', 'Differential', 'differential'),
      ('sys-adjustments', 'Adjustments', 'adjustments'),
      ('sys-opening', 'Opening', 'opening'),
    ];
    for (final (id, name, role) in seeds) {
      await into(envelopes).insert(
        EnvelopesCompanion.insert(
          id: id,
          name: name,
          role: role,
          isArchived: false,
          updatedAt: epoch0,
        ),
        mode: InsertMode.insertOrIgnore,
      );
    }
  }
}
