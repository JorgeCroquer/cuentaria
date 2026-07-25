import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../features/movements/application/movements_providers.dart';
import '../../../providers/composition_root.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';

String _formatDate(DateTime date) {
  final local = date.toLocal();
  final year = local.year.toString().padLeft(4, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

String _formatUsdCents(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';

int _netUsd(Transaction transaction) => transaction.postings
    .where((p) => p.amountUsd > 0)
    .fold(0, (sum, p) => sum + p.amountUsd);

/// Icon/color for a movement row (#99): the appearance of the first user
/// Envelope it touches, matching the tagging users already did in the
/// Envelopes management screen (#95) — falls back to a generic icon for
/// account-only movements (Transfer, AcquisitionConversion).
class MovementVisual {
  const MovementVisual({required this.icon, this.color});

  final IconData icon;
  final Color? color;
}

MovementVisual movementVisualFor(
  Transaction transaction,
  CatalogRepository catalog,
) {
  for (final posting in transaction.postings) {
    final target = posting.target;
    if (target is! EnvelopeTarget) continue;
    final envelope = catalog.getEnvelope(target.envelopeId);
    if (envelope == null || envelope.role != EnvelopeRole.none) continue;
    final appearance = envelope.appearance;
    return MovementVisual(
      icon: AppIcons.iconFor(appearance.iconId),
      color:
          appearance.colorIndex == null
              ? null
              : AppColors.palette[appearance.colorIndex! %
                  AppColors.palette.length],
    );
  }
  return const MovementVisual(icon: Icons.receipt_long_outlined);
}

/// Chronological Movements screen (#99): replaces the old Ledger tab and
/// its income form. Read-only list over [EventStore.queryLog] via
/// [movementsListProvider]; tapping a row opens the detail/reversal screen.
class MovementsScreen extends ConsumerWidget {
  const MovementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movementsAsync = ref.watch(movementsListProvider);
    final catalogAsync = ref.watch(catalogRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Movements')),
      body: movementsAsync.when(
        data: (transactions) {
          if (transactions.isEmpty) {
            return const Center(
              child: Text('No movements yet.', key: Key('movementsEmptyState')),
            );
          }
          return catalogAsync.when(
            data:
                (catalog) => ListView(
                  children: [
                    for (final transaction in transactions)
                      _MovementTile(transaction: transaction, catalog: catalog),
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
}

class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.transaction, required this.catalog});

  final Transaction transaction;
  final CatalogRepository catalog;

  @override
  Widget build(BuildContext context) {
    final visual = movementVisualFor(transaction, catalog);
    final note = transaction.metadata.source ?? transaction.metadata.memo;

    return ListTile(
      key: Key('movement_${transaction.metadata.eventId.value}'),
      leading: Icon(visual.icon, color: visual.color),
      title: Text(transaction.metadata.type),
      subtitle: Text(
        note == null
            ? _formatDate(transaction.metadata.occurredAt.value)
            : '${_formatDate(transaction.metadata.occurredAt.value)} · $note',
      ),
      trailing: Text(_formatUsdCents(_netUsd(transaction))),
      onTap:
          () =>
              context.push('/movements/${transaction.metadata.eventId.value}'),
    );
  }
}
