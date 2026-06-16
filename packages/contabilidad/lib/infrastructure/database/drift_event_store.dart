/// Drift-backed implementation of [EventStore].
///
/// Behaviors implemented in slice #42:
///   - [append]: atomic — writes [events] row + all [event_targets] rows in a
///     single Drift transaction, using INSERT OR IGNORE for dedup. Returns false
///     when the event_id already exists (idempotent no-op, no exception).
///   - [get]: decodes the stored payload via [EventCodec] and returns the
///     reconstructed [Transaction], or null if not found.
///
/// Deferred to slice #43:
///   - [hasReversal]: stub — throws [UnimplementedError].
///   - [queryLog]: stub — throws [UnimplementedError].
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
  // hasReversal — deferred to slice #43
  // -------------------------------------------------------------------------

  @override
  Future<bool> hasReversal(EventId originalId) {
    throw UnimplementedError('hasReversal lands in slice #43');
  }

  // -------------------------------------------------------------------------
  // queryLog — deferred to slice #43
  // -------------------------------------------------------------------------

  @override
  Future<List<Transaction>> queryLog({LogFilters? filters}) {
    throw UnimplementedError('queryLog lands in slice #43');
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
