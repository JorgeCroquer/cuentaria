/// Drift database definition for Cuentaria — schema v1.
///
/// Two version counters (F2-8):
///   - [schemaVersion] (= 1): Drift structural schema version → controls
///     `MigrationStrategy` and table DDL.
///   - `schema_version` column inside `events.payload`: event-shape version,
///     used by [EventCodec] upcaster registry. Starts at 1 (identity upcast).
///
/// Tables:
///   - [events]: canonical event log (append-only).
///   - [event_targets]: derived index rows for account/envelope queries.
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
// Database
// ---------------------------------------------------------------------------

@DriftDatabase(tables: [Events, EventTargets])
class CuentariaDatabase extends _$CuentariaDatabase {
  CuentariaDatabase(super.e);

  /// Drift structural schema version. Increment when tables change.
  /// See also [schemaVersion] column in [events] (different counter — F2-8).
  @override
  int get schemaVersion => 1;

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
    },
  );
}
