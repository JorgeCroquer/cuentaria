import 'package:shared_kernel/shared_kernel.dart';
import '../transaction.dart';
import 'log_filters.dart';

abstract class EventStore {
  Future<bool> append(Transaction event);
  Future<Transaction?> get(EventId id);
  Future<bool> hasReversal(EventId originalId);
  Future<List<Transaction>> queryLog({LogFilters? filters});

  /// Returns raw event payload strings in canonical order
  /// `(occurred_at, recorded_at, event_id)`, matching [filters] exactly as
  /// [queryLog] would.
  ///
  /// Unlike [queryLog], payloads are returned as stored — never decoded and
  /// re-encoded — so a Backup File built from them is byte-identical to
  /// `events.payload` even for an event whose `schema_version` an upcaster
  /// would otherwise rewrite (ADR-0021 §2).
  Future<List<String>> queryRawPayloads({LogFilters? filters});
}
