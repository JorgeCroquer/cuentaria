import 'package:shared_kernel/shared_kernel.dart';
import '../transaccion.dart';
import 'filtros_log.dart';

abstract class EventStore {
  Future<bool> append(Transaccion event);
  Future<Transaccion?> get(EventId id);
  Future<bool> hasReversal(EventId originalId);
  Future<List<Transaccion>> consultarLog({FiltrosLog? filtros});
}
