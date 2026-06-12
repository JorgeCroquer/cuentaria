import 'package:shared_kernel/shared_kernel.dart';
import '../transaccion.dart';

abstract class EventStore {
  Future<bool> append(Transaccion event);
  Future<Transaccion?> get(EventId id);
  Future<bool> hasReversal(EventId originalId);
}
