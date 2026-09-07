import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/widgets.dart';
import '../../../features/movements/application/movements_providers.dart';
import '../../../providers/composition_root.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import 'movement_labels.dart';

String _formatDate(DateTime date) {
  final local = date.toLocal();
  final year = local.year.toString().padLeft(4, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

String _formatUsdCents(int cents) {
  final sign = cents < 0 ? '-' : '';
  return '$sign\$${(cents.abs() / 100).toStringAsFixed(2)}';
}

/// Same as [_formatUsdCents] but with an explicit `+` for positive amounts —
/// used for day subtotals, where sign alone (via color) isn't enough to tell
/// "no movements summed" from "net positive day" at a glance.
String _formatSignedUsdCents(int cents) {
  final sign = cents < 0 ? '-' : (cents > 0 ? '+' : '');
  return '$sign\$${(cents.abs() / 100).toStringAsFixed(2)}';
}

AmountSign _signFor(int cents) {
  if (cents < 0) return AmountSign.negative;
  if (cents > 0) return AmountSign.positive;
  return AmountSign.neutral;
}

const _spanishMonthAbbreviations = [
  'ENE',
  'FEB',
  'MAR',
  'ABR',
  'MAY',
  'JUN',
  'JUL',
  'AGO',
  'SEP',
  'OCT',
  'NOV',
  'DIC',
];

/// Local calendar day (midnight, device timezone) a [DomainTimestamp] falls
/// on — the day cutoff is hour-local, same doctrine as ADR-0024 §4, so a
/// transaction near midnight UTC still groups under the day the user lived
/// it in.
DateTime _localDay(DateTime dateTime) {
  final local = dateTime.toLocal();
  return DateTime(local.year, local.month, local.day);
}

String _dayGroupLabel(DateTime day, DateTime today) {
  final monthLabel = '${day.day} ${_spanishMonthAbbreviations[day.month - 1]}';
  if (day == today) return 'HOY · $monthLabel';
  if (day == today.subtract(const Duration(days: 1))) {
    return 'AYER · $monthLabel';
  }
  return monthLabel;
}

/// Day subtotal (#282): sum of [_netUsd] across the day's movements, minus
/// inter-account moves (Transfer, AcquisitionConversion, ...) — those net to
/// zero on the ledger by construction and shouldn't inflate/deflate the
/// day's real financial movement.
int _daySubtotal(List<Transaction> transactions) => transactions
    .where((transaction) => !_isInterAccountMove(transaction))
    .fold(0, (sum, transaction) => sum + _netUsd(transaction));

/// True for an inter-account move (Transfer, AcquisitionConversion): every
/// posting is on the Account dimension, none on Envelope. The self-balancing
/// invariant in [Transaction.create] then forces the Account postings to net
/// to zero, since there is no Envelope side to balance against.
bool _isInterAccountMove(Transaction transaction) =>
    transaction.postings.every((p) => p.dimension == Dimension.account);

/// USD amount to show on a movement row.
///
/// For most families this is the net moved on the Account dimension only —
/// the same `sumAccounts` the self-balancing invariant already computes in
/// [Transaction.create]. Summing every posting regardless of dimension
/// double-counts (an Income's Account and Envelope legs carry the same
/// signed amount) and zeroes out Expenses (both legs are negative, so a
/// `> 0` filter drops them all).
///
/// For an inter-account move that net is always zero by the invariant above
/// — accounting-correct (no wealth was created) but reads as a bug in the
/// list ("Mover — $0.00" for a real $100 transfer). So for this family we
/// show the moved amount (the receiving leg) instead; net wealth is
/// unaffected, this only changes what the row displays.
int _netUsd(Transaction transaction) {
  final accountPostings = transaction.postings.where(
    (p) => p.dimension == Dimension.account,
  );
  if (_isInterAccountMove(transaction)) {
    return accountPostings
        .map((p) => p.amountUsd)
        .reduce((a, b) => a > b ? a : b);
  }
  return accountPostings.fold(0, (sum, p) => sum + p.amountUsd);
}

/// Icon/color for a movement row (#99): the appearance of the first user
/// Envelope it touches, matching the tagging users already did in the
/// Envelopes management screen (#95) — falls back to a generic icon for
/// account-only movements (Transfer, AcquisitionConversion). A reversal
/// always gets its own icon (#282): reusing the reversed envelope's
/// appearance would render identically to the movement it undoes.
class MovementVisual {
  const MovementVisual({required this.icon, this.color});

  final IconData icon;
  final Color? color;
}

MovementVisual movementVisualFor(
  Transaction transaction,
  CatalogRepository catalog,
) {
  if (transaction.metadata.reverses != null) {
    return const MovementVisual(icon: Icons.undo);
  }
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
      appBar: AppBar(title: const Text('Movimientos')),
      body: movementsAsync.when(
        data: (transactions) {
          if (transactions.isEmpty) {
            return const Center(
              child: Text(
                'Sin movimientos aún.',
                key: Key('movementsEmptyState'),
              ),
            );
          }
          return catalogAsync.when(
            data:
                (catalog) => _MovementsList(
                  transactions: transactions,
                  catalog: catalog,
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
}

/// Movements grouped by local calendar day (#282), newest day first —
/// [movementsListProvider] already sorts the feed newest-first, so grouping
/// by first-seen day preserves that order without a manual sort.
class _MovementsList extends StatelessWidget {
  const _MovementsList({required this.transactions, required this.catalog});

  final List<Transaction> transactions;
  final CatalogRepository catalog;

  @override
  Widget build(BuildContext context) {
    final byEventId = {
      for (final transaction in transactions)
        transaction.metadata.eventId.value: transaction,
    };
    final today = _localDay(DateTime.now());

    final groups = <DateTime, List<Transaction>>{};
    for (final transaction in transactions) {
      final day = _localDay(transaction.metadata.occurredAt.value);
      groups.putIfAbsent(day, () => []).add(transaction);
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        for (final entry in groups.entries) ...[
          _DayGroupCard(
            day: entry.key,
            today: today,
            transactions: entry.value,
            catalog: catalog,
            byEventId: byEventId,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }
}

class _DayGroupCard extends StatelessWidget {
  const _DayGroupCard({
    required this.day,
    required this.today,
    required this.transactions,
    required this.catalog,
    required this.byEventId,
  });

  final DateTime day;
  final DateTime today;
  final List<Transaction> transactions;
  final CatalogRepository catalog;
  final Map<String, Transaction> byEventId;

  @override
  Widget build(BuildContext context) {
    final subtotal = _daySubtotal(transactions);
    final dayKey = _formatDate(day);

    return SectionCard(
      header: _dayGroupLabel(day, today),
      headerKey: Key('dayHeader_$dayKey'),
      trailing: SignedAmountText(
        textKey: Key('daySubtotal_$dayKey'),
        amount: _formatSignedUsdCents(subtotal),
        sign: _signFor(subtotal),
      ),
      showDividers: true,
      children: [
        for (final transaction in transactions)
          _MovementTile(
            transaction: transaction,
            catalog: catalog,
            byEventId: byEventId,
          ),
      ],
    );
  }
}

String? _subtitleFor(
  Transaction transaction,
  Map<String, Transaction> byEventId,
) {
  final metadata = transaction.metadata;
  final note = metadata.source ?? metadata.memo;
  final reverses = metadata.reverses;
  if (reverses == null) return note;

  final original = byEventId[reverses.value];
  final description =
      original == null
          ? 'Deshace un movimiento'
          : 'Deshace ${humanMovementLabel(original.metadata.type)}';
  return note == null ? description : '$description · $note';
}

class _MovementTile extends StatelessWidget {
  const _MovementTile({
    required this.transaction,
    required this.catalog,
    required this.byEventId,
  });

  final Transaction transaction;
  final CatalogRepository catalog;
  final Map<String, Transaction> byEventId;

  @override
  Widget build(BuildContext context) {
    final visual = movementVisualFor(transaction, catalog);
    final subtitle = _subtitleFor(transaction, byEventId);
    final netUsd = _netUsd(transaction);
    final sign =
        _isInterAccountMove(transaction)
            ? AmountSign.neutral
            : _signFor(netUsd);

    return ListTile(
      key: Key('movement_${transaction.metadata.eventId.value}'),
      leading: Icon(visual.icon, color: visual.color),
      title: Text(humanMovementLabel(transaction.metadata.type)),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: SignedAmountText(amount: _formatUsdCents(netUsd), sign: sign),
      onTap:
          () =>
              context.push('/movements/${transaction.metadata.eventId.value}'),
    );
  }
}
