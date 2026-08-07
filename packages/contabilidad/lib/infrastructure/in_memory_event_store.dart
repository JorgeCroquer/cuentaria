import 'package:shared_kernel/shared_kernel.dart';
import '../domain/transaction.dart';
import '../domain/ports/event_store.dart';
import '../domain/ports/log_filters.dart';
import '../domain/posting_target.dart';
import 'codec/event_codec.dart';

class InMemoryEventStore implements EventStore {
  final Map<EventId, Transaction> _store = {};
  final EventCodec _codec = const EventCodec();

  @override
  Future<bool> append(Transaction event) async {
    final eventId = event.metadata.eventId;
    if (_store.containsKey(eventId)) {
      return false; // deduplicated
    }

    _store[eventId] = event;
    return true; // inserted successfully
  }

  @override
  Future<Transaction?> get(EventId id) async {
    return _store[id];
  }

  @override
  Future<bool> hasReversal(EventId originalId) async {
    return _store.values.any((tx) => tx.metadata.reverses == originalId);
  }

  @override
  Future<List<Transaction>> queryLog({LogFilters? filters}) async {
    Iterable<Transaction> result = _store.values;

    if (filters != null) {
      if (filters.account != null) {
        result = result.where(
          (tx) => tx.postings.any((p) {
            final target = p.target;
            return target is AccountTarget &&
                target.accountId == filters.account;
          }),
        );
      }

      if (filters.envelope != null) {
        result = result.where(
          (tx) => tx.postings.any((p) {
            final target = p.target;
            return target is EnvelopeTarget &&
                target.envelopeId == filters.envelope;
          }),
        );
      }

      if (filters.from != null) {
        result = result.where(
          (tx) =>
              tx.metadata.occurredAt.value.isAfter(filters.from!.value) ||
              tx.metadata.occurredAt.value.isAtSameMomentAs(
                filters.from!.value,
              ),
        );
      }

      if (filters.to != null) {
        result = result.where(
          (tx) =>
              tx.metadata.occurredAt.value.isBefore(filters.to!.value) ||
              tx.metadata.occurredAt.value.isAtSameMomentAs(filters.to!.value),
        );
      }
    }

    final list = result.toList()..sort(_canonicalOrder);
    return list;
  }

  @override
  Future<List<String>> queryRawPayloads({LogFilters? filters}) async {
    final transactions = await queryLog(filters: filters);
    return transactions.map(_codec.encode).toList();
  }

  // Canonical order C1-9: occurredAt -> recordedAt -> eventId.
  static int _canonicalOrder(Transaction a, Transaction b) {
    final cmp1 = a.metadata.occurredAt.value.compareTo(
      b.metadata.occurredAt.value,
    );
    if (cmp1 != 0) return cmp1;

    final cmp2 = a.metadata.recordedAt.value.compareTo(
      b.metadata.recordedAt.value,
    );
    if (cmp2 != 0) return cmp2;

    return a.metadata.eventId.value.compareTo(b.metadata.eventId.value);
  }

  /// Exposed for testing and simple querying purposes only.
  List<Transaction> get events {
    final list = _store.values.toList()..sort(_canonicalOrder);
    return list;
  }
}
