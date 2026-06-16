import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:event_bus/event_bus.dart';
import '../domain/transaction.dart';
import '../domain/transaction_metadata.dart';
import '../domain/posting.dart';
import '../domain/ports/event_store.dart';
import '../domain/ports/ledger_projections.dart';

class RecordTransaction {
  final EventStore _store;
  final LedgerProjections _projections;
  final EventBus _eventBus;
  final ReferentialIntegrityValidator _validator;

  RecordTransaction({
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
    required TransactionMetadata metadata,
  }) async {
    _validator.validate(postings);

    final tx = Transaction.create(postings: postings, metadata: metadata);

    final isNew = await _store.append(tx);

    if (isNew) {
      _projections.apply(tx);
      _eventBus.publish(tx);
    }
  }
}
