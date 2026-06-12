import 'package:contabilidad/domain/ports/event_store.dart';
import 'package:contabilidad/domain/ports/ledger_projections.dart';

class ReconstruirProyecciones {
  final EventStore _store;
  final LedgerProjections _projections;

  ReconstruirProyecciones({
    required EventStore store,
    required LedgerProjections projections,
  })  : _store = store,
        _projections = projections;

  Future<void> execute() async {
    _projections.limpiar();
    
    // Obtenemos todos los eventos (se retornan ordenados determinísticamente)
    final eventos = await _store.consultarLog();
    
    for (final event in eventos) {
      _projections.aplicar(event);
    }
  }
}
