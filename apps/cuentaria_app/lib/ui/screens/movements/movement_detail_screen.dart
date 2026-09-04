import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_kernel/shared_kernel.dart';

import '../../../features/movements/application/movements_providers.dart';
import '../../../providers/composition_root.dart';
import 'movement_labels.dart';

String _formatDate(DateTime date) {
  final local = date.toLocal();
  final year = local.year.toString().padLeft(4, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

String _formatSignedUsd(int cents) {
  final sign = cents < 0 ? '-' : '+';
  return '$sign\$${(cents.abs() / 100).toStringAsFixed(2)}';
}

String _targetLabel(PostingTarget target, CatalogRepository catalog) {
  if (target is AccountTarget) {
    return catalog.getAccount(target.accountId)?.name ?? target.accountId.value;
  }
  final envelopeTarget = target as EnvelopeTarget;
  return catalog.getEnvelope(envelopeTarget.envelopeId)?.name ??
      envelopeTarget.envelopeId.value;
}

/// Movement detail (#99): postings, date, note/source and the **Reversar**
/// action — appends an exact negation via the existing [RecordReversal]
/// factory. Already-reversed movements (and reversals themselves) show it
/// instead of the action, guarded by [reversalStatusProvider] /
/// [EventStore.hasReversal] (double-reversal guard).
class MovementDetailScreen extends ConsumerStatefulWidget {
  const MovementDetailScreen({super.key, required this.eventId});

  final EventId eventId;

  @override
  ConsumerState<MovementDetailScreen> createState() =>
      _MovementDetailScreenState();
}

class _MovementDetailScreenState extends ConsumerState<MovementDetailScreen> {
  bool _isReversing = false;
  String? _error;

  Future<void> _reverse() async {
    setState(() {
      _error = null;
      _isReversing = true;
    });

    try {
      final recordReversal = await ref.read(recordReversalProvider.future);
      final deviceId = await ref.read(deviceIdProvider.future);

      await recordReversal(
        eventId: EventId(DateTime.now().microsecondsSinceEpoch.toString()),
        deviceId: deviceId,
        originalEventId: widget.eventId,
      );

      ref.invalidate(reversalStatusProvider(widget.eventId));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isReversing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final transactionAsync = ref.watch(transactionProvider(widget.eventId));
    final hasReversalAsync = ref.watch(reversalStatusProvider(widget.eventId));
    final catalogAsync = ref.watch(catalogRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Movimiento')),
      body: transactionAsync.when(
        data: (transaction) {
          if (transaction == null) {
            return const Center(
              child: Text(
                'Movimiento no encontrado.',
                key: Key('movementNotFound'),
              ),
            );
          }
          return catalogAsync.when(
            data:
                (catalog) => hasReversalAsync.when(
                  data:
                      (hasReversal) =>
                          _buildBody(transaction, catalog, hasReversal),
                  loading:
                      () => const Center(child: CircularProgressIndicator()),
                  error:
                      (error, stackTrace) =>
                          Center(child: Text('No se pudo cargar: $error')),
                ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error:
                (error, stackTrace) =>
                    Center(child: Text('No se pudo cargar: $error')),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error:
            (error, stackTrace) =>
                Center(child: Text('No se pudo cargar: $error')),
      ),
    );
  }

  Widget _buildBody(
    Transaction transaction,
    CatalogRepository catalog,
    bool hasReversal,
  ) {
    final metadata = transaction.metadata;
    final isReversal = metadata.reverses != null;
    final note = metadata.source ?? metadata.memo;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          humanMovementLabel(metadata.type),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text(
          _formatDate(metadata.occurredAt.value),
          key: const Key('movementDate'),
        ),
        if (note != null) Text(note, key: const Key('movementNote')),
        const Divider(height: 32),
        for (var i = 0; i < transaction.postings.length; i++)
          ListTile(
            key: Key('posting_$i'),
            title: Text(_targetLabel(transaction.postings[i].target, catalog)),
            trailing: Text(_formatSignedUsd(transaction.postings[i].amountUsd)),
          ),
        const SizedBox(height: 24),
        if (isReversal)
          const Text(
            'Este movimiento es un reverso.',
            key: Key('isReversalNotice'),
          )
        else if (hasReversal)
          const Text('Ya reversado', key: Key('alreadyReversedNotice'))
        else
          ElevatedButton(
            key: const Key('reverseButton'),
            onPressed: _isReversing ? null : _reverse,
            child: const Text('Reversar'),
          ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}
