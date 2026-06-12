import 'package:shared_kernel/shared_kernel.dart';
import '../domain/transaccion.dart';
import '../domain/ports/event_store.dart';
import '../domain/ports/filtros_log.dart';
import '../domain/posting_target.dart';

class InMemoryEventStore implements EventStore {
  final Map<EventId, Transaccion> _store = {};

  @override
  Future<bool> append(Transaccion event) async {
    final eventId = event.metadata.eventId;
    if (_store.containsKey(eventId)) {
      return false; // deduplicado
    }

    _store[eventId] = event;
    return true; // insertado exitosamente
  }

  @override
  Future<Transaccion?> get(EventId id) async {
    return _store[id];
  }

  @override
  Future<bool> hasReversal(EventId originalId) async {
    return _store.values.any((tx) => tx.metadata.reverses == originalId);
  }

  @override
  Future<List<Transaccion>> consultarLog({FiltrosLog? filtros}) async {
    Iterable<Transaccion> result = _store.values;

    if (filtros != null) {
      if (filtros.cuenta != null) {
        result = result.where((tx) => tx.postings.any((p) {
          final target = p.target;
          return target is CuentaTarget && target.accountId == filtros.cuenta;
        }));
      }

      if (filtros.sobre != null) {
        result = result.where((tx) => tx.postings.any((p) {
          final target = p.target;
          return target is SobreTarget && target.envelopeId == filtros.sobre;
        }));
      }

      if (filtros.desde != null) {
        result = result.where((tx) =>
            tx.metadata.occurredAt.value.isAfter(filtros.desde!.value) ||
            tx.metadata.occurredAt.value.isAtSameMomentAs(filtros.desde!.value));
      }

      if (filtros.hasta != null) {
        result = result.where((tx) =>
            tx.metadata.occurredAt.value.isBefore(filtros.hasta!.value) ||
            tx.metadata.occurredAt.value.isAtSameMomentAs(filtros.hasta!.value));
      }
    }

    final list = result.toList();
    list.sort((a, b) {
      final cmp1 = a.metadata.occurredAt.value.compareTo(b.metadata.occurredAt.value);
      if (cmp1 != 0) return cmp1;

      final cmp2 = a.metadata.recordedAt.value.compareTo(b.metadata.recordedAt.value);
      if (cmp2 != 0) return cmp2;

      return a.metadata.eventId.value.compareTo(b.metadata.eventId.value);
    });

    return list;
  }

  /// Expuesto solo para propósitos de testing y consulta simple.
  List<Transaccion> get events {
    final list = _store.values.toList();
    list.sort((a, b) {
      final cmp1 = a.metadata.occurredAt.value.compareTo(b.metadata.occurredAt.value);
      if (cmp1 != 0) return cmp1;

      final cmp2 = a.metadata.recordedAt.value.compareTo(b.metadata.recordedAt.value);
      if (cmp2 != 0) return cmp2;

      return a.metadata.eventId.value.compareTo(b.metadata.eventId.value);
    });
    return list;
  }
}
