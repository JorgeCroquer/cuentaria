import 'package:shared_kernel/shared_kernel.dart';
import '../domain/transaccion.dart';
import '../domain/ports/event_store.dart';

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

  /// Expuesto solo para propósitos de testing y consulta simple.
  List<Transaccion> get events => _store.values.toList();
}
