/// Drift-backed implementation of [EventStore].
///
/// Slice #42:
///   - [append]: atomic — writes [events] row + all [event_targets] rows in a
///     single Drift transaction, using INSERT OR IGNORE for dedup. Returns false
///     when the event_id already exists (idempotent no-op, no exception).
///   - [get]: decodes the stored payload via [EventCodec] and returns the
///     reconstructed [Transaction], or null if not found.
///
/// Slice #43:
///   - [queryLog]: returns events in canonical order `(occurred_at, recorded_at,
///     event_id)` with optional filters by account/envelope (via `event_targets`
///     index) and date range (on `occurred_at`). Filters compose with AND.
///   - [hasReversal]: returns true iff any stored event has `reverses = originalId`.
///
/// The [QueryExecutor] is injected through [CuentariaDatabase], so this class
/// stays Flutter-free and testable with [NativeDatabase.memory()].
library;

import 'package:drift/drift.dart';
import 'package:shared_kernel/shared_kernel.dart';

import '../../domain/ports/event_store.dart';
import '../../domain/ports/log_filters.dart';
import '../../domain/posting_target.dart';
import '../../domain/transaction.dart';
import '../codec/event_codec.dart';
import 'cuentaria_database.dart';

class DriftEventStore implements EventStore {
  final CuentariaDatabase _db;
  final EventCodec _codec;

  DriftEventStore(this._db, {EventCodec codec = const EventCodec()})
    : _codec = codec;

  // -------------------------------------------------------------------------
  // append
  // -------------------------------------------------------------------------

  @override
  Future<bool> append(Transaction event) async {
    final meta = event.metadata;
    final eventIdStr = meta.eventId.value;

    final payload = _codec.encode(event);
    final occurredAtUs = meta.occurredAt.value.microsecondsSinceEpoch;
    final recordedAtUs = meta.recordedAt.value.microsecondsSinceEpoch;

    final targets = _deriveTargets(event);

    // Dedup + write happen atomically. INSERT OR IGNORE skips on PK conflict;
    // we detect duplicate by checking affected row count.
    bool inserted = false;
    await _db.transaction(() async {
      final rowsAffected = await _db
          .into(_db.events)
          .insertReturningOrNull(
            EventsCompanion.insert(
              eventId: eventIdStr,
              type: meta.type,
              occurredAt: occurredAtUs,
              recordedAt: recordedAtUs,
              schemaVersion: meta.schemaVersion,
              reverses: Value(meta.reverses?.value),
              payload: payload,
            ),
            mode: InsertMode.insertOrIgnore,
          );

      if (rowsAffected == null) {
        // PK conflict — already exists, no-op.
        inserted = false;
        return;
      }

      inserted = true;

      for (final target in targets) {
        await _db
            .into(_db.eventTargets)
            .insert(target, mode: InsertMode.insertOrIgnore);
      }
    });

    return inserted;
  }

  // -------------------------------------------------------------------------
  // get
  // -------------------------------------------------------------------------

  @override
  Future<Transaction?> get(EventId id) async {
    final row =
        await (_db.select(_db.events)
          ..where((t) => t.eventId.equals(id.value))).getSingleOrNull();

    if (row == null) return null;
    return _codec.decode(row.payload);
  }

  // -------------------------------------------------------------------------
  // hasReversal
  // -------------------------------------------------------------------------

  @override
  Future<bool> hasReversal(EventId originalId) async {
    final row =
        await (_db.select(_db.events)
              ..where((t) => t.reverses.equals(originalId.value))
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  // -------------------------------------------------------------------------
  // queryLog
  // -------------------------------------------------------------------------

  /// Returns events in canonical order `(occurred_at, recorded_at, event_id)`.
  ///
  /// Filters compose with AND:
  ///   - [LogFilters.account]: JOIN with `event_targets` WHERE dimension='account'
  ///   - [LogFilters.envelope]: JOIN with `event_targets` WHERE dimension='envelope'
  ///   - [LogFilters.from] / [LogFilters.to]: epoch µs range on `occurred_at`.
  ///
  /// Account and envelope filters use the `event_targets` index — no JSON scan.
  @override
  Future<List<Transaction>> queryLog({LogFilters? filters}) async {
    // Build query with optional JOINs for account/envelope filters.
    // Drift's typed query API doesn't compose dynamic JOINs cleanly for
    // semi-arbitrary combos, so we use customSelect for the filter path.
    final rows = await _queryRows(filters);
    return rows.map((r) => _codec.decode(r.payload)).toList();
  }

  Future<List<Event>> _queryRows(LogFilters? filters) async {
    if (filters == null) {
      return (_db.select(_db.events)..orderBy([
        (t) => OrderingTerm.asc(t.occurredAt),
        (t) => OrderingTerm.asc(t.recordedAt),
        (t) => OrderingTerm.asc(t.eventId),
      ])).get();
    }

    // At least one filter active — build WHERE/JOIN via raw SQL so we can
    // compose arbitrary combinations in one query without N+1 round-trips.
    final conditions = <String>[];
    final args = <Object?>[];

    if (filters.account != null) {
      conditions.add(
        'EXISTS (SELECT 1 FROM event_targets et '
        "WHERE et.event_id = e.event_id AND et.dimension = 'account' "
        'AND et.target_id = ?)',
      );
      args.add(filters.account!.value);
    }

    if (filters.envelope != null) {
      conditions.add(
        'EXISTS (SELECT 1 FROM event_targets et '
        "WHERE et.event_id = e.event_id AND et.dimension = 'envelope' "
        'AND et.target_id = ?)',
      );
      args.add(filters.envelope!.value);
    }

    if (filters.from != null) {
      conditions.add('e.occurred_at >= ?');
      args.add(filters.from!.value.microsecondsSinceEpoch);
    }

    if (filters.to != null) {
      conditions.add('e.occurred_at <= ?');
      args.add(filters.to!.value.microsecondsSinceEpoch);
    }

    final where = conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';

    final sql =
        'SELECT e.event_id, e.type, e.occurred_at, e.recorded_at, '
        'e.schema_version, e.reverses, e.payload '
        'FROM events e '
        '$where '
        'ORDER BY e.occurred_at ASC, e.recorded_at ASC, e.event_id ASC';

    final result =
        await _db
            .customSelect(
              sql,
              variables: [for (final arg in args) Variable(arg)],
            )
            .get();

    return result
        .map(
          (row) => Event(
            eventId: row.read<String>('event_id'),
            type: row.read<String>('type'),
            occurredAt: row.read<int>('occurred_at'),
            recordedAt: row.read<int>('recorded_at'),
            schemaVersion: row.read<int>('schema_version'),
            reverses: row.readNullable<String>('reverses'),
            payload: row.read<String>('payload'),
          ),
        )
        .toList();
  }

  // -------------------------------------------------------------------------
  // Private helpers
  // -------------------------------------------------------------------------

  /// Returns [EventTargetsCompanion] rows derived from [event]'s postings.
  ///
  /// Each distinct (dimension, targetId) pair from postings becomes one row.
  List<EventTargetsCompanion> _deriveTargets(Transaction event) {
    final seen = <String>{};
    final result = <EventTargetsCompanion>[];
    final eventIdStr = event.metadata.eventId.value;

    for (final posting in event.postings) {
      final dimension = switch (posting.target) {
        AccountTarget() => 'account',
        EnvelopeTarget() => 'envelope',
      };
      final targetId = switch (posting.target) {
        AccountTarget(:final accountId) => accountId.value,
        EnvelopeTarget(:final envelopeId) => envelopeId.value,
      };
      final key = '$dimension:$targetId';
      if (seen.add(key)) {
        result.add(
          EventTargetsCompanion.insert(
            eventId: eventIdStr,
            dimension: dimension,
            targetId: targetId,
          ),
        );
      }
    }

    return result;
  }
}
