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
///
/// A Distribution (#309) has no Account posting at all, so this always nets
/// to $0.00 for it — the same "relabeling, not new wealth" story as an
/// inter-account move, already rendered with a neutral sign below since
/// [_signFor] treats 0 as neutral.
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
/// appearance would render identically to the movement it undoes. An
/// Adjustment (reconciliation) also gets its own icon: it posts to the
/// system Adjustments envelope, which carries no user appearance.
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
  if (transaction.metadata.type == 'Adjustment') {
    return const MovementVisual(icon: Icons.fact_check_outlined);
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

    return Column(
      key: Key('dayGroup_$dayKey'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xs,
          ),
          child: DayGroupHeader(
            key: Key('dayHeader_$dayKey'),
            label: _dayGroupLabel(day, today),
            amount: _formatSignedUsdCents(subtotal),
            sign: _signFor(subtotal),
            amountKey: Key('daySubtotal_$dayKey'),
          ),
        ),
        Card(
          child: Column(
            children: [
              for (var i = 0; i < transactions.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _MovementTile(
                  transaction: transactions[i],
                  catalog: catalog,
                  byEventId: byEventId,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The envelope of the first Envelope posting a movement touches — used to
/// name an Expense row after what it was actually spent on.
String? _envelopeNameFor(Transaction transaction, CatalogRepository catalog) {
  for (final posting in transaction.postings) {
    final target = posting.target;
    if (target is EnvelopeTarget) {
      return catalog.getEnvelope(target.envelopeId)?.name;
    }
  }
  return null;
}

/// The single Account posting's account name — used to name the account a
/// row's money actually sat in.
String? _accountPostingNameFor(
  Transaction transaction,
  CatalogRepository catalog,
) {
  for (final posting in transaction.postings) {
    final target = posting.target;
    if (target is AccountTarget) {
      return catalog.getAccount(target.accountId)?.name;
    }
  }
  return null;
}

/// `<source account> → <destination account>` for an inter-account move
/// ([_isInterAccountMove]): the negative leg is where the money left, the
/// positive leg is where it landed (same sign convention [_netUsd] relies
/// on for these families).
String? _accountRouteFor(Transaction transaction, CatalogRepository catalog) {
  final accountPostings =
      transaction.postings.where((p) => p.target is AccountTarget).toList();
  if (accountPostings.length < 2) return null;

  final source = accountPostings.firstWhere(
    (p) => p.amountUsd < 0,
    orElse: () => accountPostings.first,
  );
  final destination = accountPostings.firstWhere(
    (p) => p.amountUsd > 0,
    orElse: () => accountPostings.last,
  );
  final sourceName =
      catalog.getAccount((source.target as AccountTarget).accountId)?.name;
  final destinationName =
      catalog.getAccount((destination.target as AccountTarget).accountId)?.name;
  return '$sourceName → $destinationName';
}

/// `<source envelope> → <destination envelope>` for a manual, one-to-one
/// Distribution (#309, Mover's "Entre sobres" submode) — same
/// negative-leg/positive-leg convention as [_accountRouteFor]. Deliberately
/// exact-two, not `>= 2`: a cascade Distribution (Apertura/Stage split into
/// several Envelopes) isn't a route between two things and keeps the
/// generic "Distribución" label instead.
String? _envelopeRouteFor(Transaction transaction, CatalogRepository catalog) {
  final envelopePostings =
      transaction.postings.where((p) => p.target is EnvelopeTarget).toList();
  if (envelopePostings.length != 2) return null;

  final source = envelopePostings.firstWhere(
    (p) => p.amountUsd < 0,
    orElse: () => envelopePostings.first,
  );
  final destination = envelopePostings.firstWhere(
    (p) => p.amountUsd > 0,
    orElse: () => envelopePostings.last,
  );
  final sourceName =
      catalog.getEnvelope((source.target as EnvelopeTarget).envelopeId)?.name;
  final destinationName =
      catalog
          .getEnvelope((destination.target as EnvelopeTarget).envelopeId)
          ?.name;
  return '$sourceName → $destinationName';
}

/// Row title (#282): distinguishes movements of the same type/amount at a
/// glance — the envelope an Expense hit, the source of an Income, or the two
/// Accounts/Envelopes a move ran between — instead of the generic family
/// label.
String _titleFor(Transaction transaction, CatalogRepository catalog) {
  final metadata = transaction.metadata;
  switch (metadata.type) {
    case 'Expense':
    case 'ForeignCurrencyExpense':
      return _envelopeNameFor(transaction, catalog) ??
          humanMovementLabel(metadata.type);
    case 'Income':
      final source = metadata.source;
      return source == null || source.isEmpty ? 'Ingreso' : 'Ingreso · $source';
    case 'Transfer':
    case 'AcquisitionConversion':
    case 'DisposalConversion':
    case 'CryptoSale':
      final route = _accountRouteFor(transaction, catalog);
      return route == null
          ? humanMovementLabel(metadata.type)
          : 'Mover · $route';
    case 'Distribution':
      final route = _envelopeRouteFor(transaction, catalog);
      return route == null
          ? humanMovementLabel(metadata.type)
          : 'Mover · $route';
    default:
      return humanMovementLabel(metadata.type);
  }
}

/// Row subtitle (#282): the Account a movement's money sat in plus its note,
/// or the reversed movement's family for a reversal.
String? _subtitleFor(
  Transaction transaction,
  CatalogRepository catalog,
  Map<String, Transaction> byEventId,
) {
  final metadata = transaction.metadata;
  final reverses = metadata.reverses;
  if (reverses != null) {
    final original = byEventId[reverses.value];
    final description =
        original == null
            ? 'Deshace un movimiento'
            : 'Deshace ${humanMovementLabel(original.metadata.type)}';
    return metadata.memo == null
        ? description
        : '$description · ${metadata.memo}';
  }

  switch (metadata.type) {
    case 'Expense':
    case 'ForeignCurrencyExpense':
    case 'Income':
      final accountName = _accountPostingNameFor(transaction, catalog);
      if (accountName == null) return metadata.memo;
      return metadata.memo == null
          ? accountName
          : '$accountName · ${metadata.memo}';
    default:
      return metadata.memo;
  }
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
    final subtitle = _subtitleFor(transaction, catalog, byEventId);
    final netUsd = _netUsd(transaction);
    final sign =
        _isInterAccountMove(transaction)
            ? AmountSign.neutral
            : _signFor(netUsd);

    return ListTile(
      key: Key('movement_${transaction.metadata.eventId.value}'),
      leading: Icon(visual.icon, color: visual.color),
      title: Text(_titleFor(transaction, catalog)),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: SignedAmountText(amount: _formatUsdCents(netUsd), sign: sign),
      onTap:
          () =>
              context.push('/movements/${transaction.metadata.eventId.value}'),
    );
  }
}
