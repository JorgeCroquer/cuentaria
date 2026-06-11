import '../transaccion.dart';

abstract class EventStore {
  Future<bool> append(Transaccion event);
}
