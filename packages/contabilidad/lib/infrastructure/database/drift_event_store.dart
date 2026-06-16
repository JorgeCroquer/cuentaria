/// Drift-backed implementation of [EventStore].
///
/// Behaviors:
///   - [append]: atomic — writes [events] row + all [event_targets] rows in a
///     single Drift transaction. Deduplicates by [event_id] PK; returns false
///     on duplicate (no-op, no exception).
///   - [get]: decodes the stored payload via [EventCodec] and returns the
///     reconstructed [Transaction], or null if not found.
///   - [hasReversal]: checks [events.reverses] column for any row reversing
///     the given [EventId].
///   - [queryLog]: returns events in canonical order
///     (occurred_at → recorded_at → event_id), optionally filtered via
///     [LogFilters].
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

    // Check for existing row — deduplicate without relying on exception paths.
    final existing =
        await (_db.select(_db.events)
          ..where((t) => t.eventId.equals(eventIdStr))).getSingleOrNull();

    if (existing != null) {
      return false; // idempotent no-op
    }

    final payload = _codec.encode(event);
    final occurredAtUs = meta.occurredAt.value.microsecondsSinceEpoch;
    final recordedAtUs = meta.recordedAt.value.microsecondsSinceEpoch;

    // Derive target rows from postings (one row per distinct dimension+id pair).
    final targets = _deriveTargets(event);

    await _db.transaction(() async {
      await _db
          .into(_db.events)
          .insert(
            EventsCompanion.insert(
              eventId: eventIdStr,
              type: meta.type,
              occurredAt: occurredAtUs,
              recordedAt: recordedAtUs,
              schemaVersion: meta.schemaVersion,
              reverses: Value(meta.reverses?.value),
              payload: payload,
            ),
          );

      for (final target in targets) {
        await _db.into(_db.eventTargets).insert(target);
      }
    });

    return true;
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
        await (_db.select(
          _db.events,
        )..where((t) => t.reverses.equals(originalId.value))).getSingleOrNull();

    return row != null;
  }

  // -------------------------------------------------------------------------
  // queryLog
  // -------------------------------------------------------------------------

  @override
  Future<List<Transaction>> queryLog({LogFilters? filters}) async {
    // Build list of event_ids matching target filters (account / envelope).
    Set<String>? matchingIds;

    if (filters?.account != null || filters?.envelope != null) {
      matchingIds = await _targetMatchingIds(filters!);
    }

    // Select events, applying date filters and target-id set filter.
    var query = _db.select(_db.events);

    query =
        query
          ..where((t) {
            Expression<bool> clause = const Constant(true);

            if (matchingIds != null) {
              clause = clause & t.eventId.isIn(matchingIds.toList());
            }

            if (filters?.from != null) {
              final fromUs = filters!.from!.value.microsecondsSinceEpoch;
              clause = clause & t.occurredAt.isBiggerOrEqualValue(fromUs);
            }

            if (filters?.to != null) {
              final toUs = filters!.to!.value.microsecondsSinceEpoch;
              clause = clause & t.occurredAt.isSmallerOrEqualValue(toUs);
            }

            return clause;
          })
          ..orderBy([
            (t) => OrderingTerm.asc(t.occurredAt),
            (t) => OrderingTerm.asc(t.recordedAt),
            (t) => OrderingTerm.asc(t.eventId),
          ]);

    final rows = await query.get();
    return rows.map((r) => _codec.decode(r.payload)).toList();
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

  /// Returns set of event_ids that have a target matching the given filters.
  Future<Set<String>> _targetMatchingIds(LogFilters filters) async {
    Set<String>? accountIds;
    Set<String>? envelopeIds;

    if (filters.account != null) {
      final rows =
          await (_db.select(_db.eventTargets)..where(
            (t) =>
                t.dimension.equals('account') &
                t.targetId.equals(filters.account!.value),
          )).get();
      accountIds = rows.map((r) => r.eventId).toSet();
    }

    if (filters.envelope != null) {
      final rows =
          await (_db.select(_db.eventTargets)..where(
            (t) =>
                t.dimension.equals('envelope') &
                t.targetId.equals(filters.envelope!.value),
          )).get();
      envelopeIds = rows.map((r) => r.eventId).toSet();
    }

    // Both filters present → intersection (event must touch both targets).
    if (accountIds != null && envelopeIds != null) {
      return accountIds.intersection(envelopeIds);
    }
    return accountIds ?? envelopeIds ?? <String>{};
  }
}
