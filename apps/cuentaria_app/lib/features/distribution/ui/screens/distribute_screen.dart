import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_kernel/shared_kernel.dart';

import '../../../../providers/composition_root.dart';
import '../../../patrimonio/application/patrimonio_providers.dart';
import '../../application/distribution_providers.dart';

String _formatUsdCents(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';

/// The distribute flow (C2), reached from Patrimonio's "Sin asignar" (S2,
/// #83): previews the saved cascade over the current Stage balance and
/// applies it on confirmation via the existing [DistributeFromStage]
/// orchestrator — no new domain logic, this is wiring only.
class DistributeScreen extends ConsumerWidget {
  const DistributeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final previewAsync = ref.watch(distributionPreviewProvider);
    final catalogAsync = ref.watch(catalogRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Distribuir Stage')),
      body: previewAsync.when(
        data: (proposal) {
          if (proposal == null) {
            return const Center(
              child: Text(
                'No cascade configured yet.',
                key: Key('noCascadeMessage'),
              ),
            );
          }
          final allocations =
              proposal.allocations.where((a) => a.amountUsd > 0).toList();
          if (allocations.isEmpty) {
            return const Center(
              child: Text(
                'Nothing to distribute.',
                key: Key('nothingToDistributeMessage'),
              ),
            );
          }
          return catalogAsync.when(
            data:
                (catalog) => ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final line in allocations)
                      ListTile(
                        title: Text(
                          catalog.getEnvelope(line.envelopeId)?.name ??
                              line.envelopeId.value,
                        ),
                        trailing: Text(_formatUsdCents(line.amountUsd)),
                      ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      key: const Key('applyDistributionButton'),
                      onPressed: () => _apply(context, ref),
                      child: const Text('Apply'),
                    ),
                  ],
                ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => Center(child: Text('Error: $error')),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('Error: $error')),
      ),
    );
  }

  Future<void> _apply(BuildContext context, WidgetRef ref) async {
    final useCase = await ref.read(distributeFromStageProvider.future);
    final deviceId = await ref.read(deviceIdProvider.future);

    await useCase.apply(
      eventId: EventId(DateTime.now().microsecondsSinceEpoch.toString()),
      deviceId: deviceId,
    );

    ref.invalidate(patrimonioSnapshotProvider);
    if (context.mounted) Navigator.of(context).pop();
  }
}
