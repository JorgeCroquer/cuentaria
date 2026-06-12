import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:event_bus/event_bus.dart';
import '../domain/transaccion.dart';
import '../domain/transaccion_metadata.dart';
import '../domain/posting.dart';
import '../domain/ports/event_store.dart';
import '../domain/ports/ledger_projections.dart';

class RegistrarTransaccion {
  final EventStore _store;
  final LedgerProjections _projections;
  final EventBus _eventBus;
  final ReferentialIntegrityValidator _validator;

  RegistrarTransaccion({
    required EventStore store,
    required LedgerProjections projections,
    required EventBus eventBus,
    required ReferentialIntegrityValidator validator,
  }) : _store = store,
       _projections = projections,
       _eventBus = eventBus,
       _validator = validator;

  Future<void> call({
    required List<Posting> postings,
    required TransaccionMetadata metadata,
  }) async {
    _validator.validate(postings);

    final tx = Transaccion.crear(postings: postings, metadata: metadata);

    final isNew = await _store.append(tx);

    if (isNew) {
      _projections.aplicar(tx);
      _eventBus.publish(tx);
    }
  }
}
