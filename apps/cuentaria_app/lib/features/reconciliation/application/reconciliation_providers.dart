import 'package:contabilidad/application/ledger/factories/record_adjustment.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/composition_root.dart';
import '../../../providers/tasas_providers.dart';
import 'reconcile_use_case.dart';

final reconcileUseCaseProvider = FutureProvider<ReconcileUseCase>((ref) async {
  final store = await ref.watch(eventStoreProvider.future);
  final catalog = await ref.watch(catalogRepositoryProvider.future);
  final projections = ref.watch(ledgerProjectionsProvider);
  final eventBus = ref.watch(eventBusProvider);
  final rateSeries = await ref.watch(rateSeriesProvider.future);

  final recordTransaction = RecordTransaction(
    store: store,
    projections: projections,
    eventBus: eventBus,
    validator: ReferentialIntegrityValidator(catalog),
  );

  return ReconcileUseCase(
    recordAdjustment: RecordAdjustment(
      record: recordTransaction,
      projections: projections,
      catalog: catalog,
    ),
    catalog: catalog,
    projections: projections,
    rateSeries: rateSeries,
  );
});
