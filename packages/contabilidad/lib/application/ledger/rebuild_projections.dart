import 'package:contabilidad/domain/ports/event_store.dart';
import 'package:contabilidad/domain/ports/ledger_projections.dart';

class RebuildProjections {
  final EventStore _store;
  final LedgerProjections _projections;

  RebuildProjections({
    required EventStore store,
    required LedgerProjections projections,
  }) : _store = store,
       _projections = projections;

  Future<void> execute() async {
    _projections.clear();

    // Fetch all events (returned in deterministic canonical order)
    final events = await _store.queryLog();

    for (final event in events) {
      _projections.apply(event);
    }
  }
}
