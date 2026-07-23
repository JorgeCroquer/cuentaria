import 'package:contabilidad/application/ledger/factories/record_income.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'composition_root.dart';

/// Records a movement (amount posted into an account and an envelope)
/// through the existing [RecordTransaction] application service, wired with
/// the composition-root adapters.
final recordIncomeProvider = FutureProvider<RecordIncome>((ref) async {
  final store = await ref.watch(eventStoreProvider.future);
  final catalog = await ref.watch(catalogRepositoryProvider.future);
  final projections = ref.watch(ledgerProjectionsProvider);
  final eventBus = ref.watch(eventBusProvider);

  final recordTransaction = RecordTransaction(
    store: store,
    projections: projections,
    eventBus: eventBus,
    validator: ReferentialIntegrityValidator(catalog),
  );

  return RecordIncome(record: recordTransaction, catalog: catalog);
});
