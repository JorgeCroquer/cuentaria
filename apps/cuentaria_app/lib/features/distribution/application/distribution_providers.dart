import 'package:contabilidad/application/cascade/distribute_from_stage.dart';
import 'package:contabilidad/application/cascade/distribution_proposal.dart';
import 'package:contabilidad/application/ledger/factories/record_distribution.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/composition_root.dart';

/// Wires the existing C2 orchestrator ([DistributeFromStage], ADR-0015) with
/// the composition-root adapters, so Patrimonio's "Sin asignar" (S2, #83)
/// can preview and apply the saved cascade without a dedicated screen for
/// editing it.
final distributeFromStageProvider = FutureProvider<DistributeFromStage>((
  ref,
) async {
  final store = await ref.watch(eventStoreProvider.future);
  final catalog = await ref.watch(catalogRepositoryProvider.future);
  final projections = ref.watch(ledgerProjectionsProvider);
  final eventBus = ref.watch(eventBusProvider);
  final cascadeRepo = await ref.watch(cascadeRepositoryProvider.future);

  final recordTransaction = RecordTransaction(
    store: store,
    projections: projections,
    eventBus: eventBus,
    validator: ReferentialIntegrityValidator(catalog),
  );

  return DistributeFromStage(
    projections: projections,
    catalog: catalog,
    cascadeRepo: cascadeRepo,
    recordDistribution: RecordDistribution(
      record: recordTransaction,
      catalog: catalog,
    ),
  );
});

/// Previews the saved cascade run over the current Stage balance — null
/// when no cascade has been saved yet.
final distributionPreviewProvider = FutureProvider<DistributionProposal?>((
  ref,
) async {
  final useCase = await ref.watch(distributeFromStageProvider.future);
  return useCase.preview();
});
