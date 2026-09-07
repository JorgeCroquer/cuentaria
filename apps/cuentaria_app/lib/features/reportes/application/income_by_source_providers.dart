import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reportes/reportes.dart';

import '../../../providers/composition_root.dart';
import 'envelope_role_mapper.dart';

const _engine = IncomeBySourceEngine();

/// One row of the Ingreso por fuente section: a `source` label's income this
/// month against the same figure a full previous month ago (ADR-0024 §4).
class IncomeRow {
  final String label;
  final int amountUsdCents;
  final int previousAmountUsdCents;

  const IncomeRow({
    required this.label,
    required this.amountUsdCents,
    required this.previousAmountUsdCents,
  });

  /// Null when there is nothing to compare against — a brand-new source
  /// with no income last month has no meaningful percentage change.
  double? get changePercent {
    if (previousAmountUsdCents == 0) return null;
    return (amountUsdCents - previousAmountUsdCents) /
        previousAmountUsdCents.abs() *
        100;
  }
}

/// The Ingreso por fuente section's data (ADR-0024 §7): rows sorted highest
/// income first.
class IncomeBySourceResult {
  final List<IncomeRow> rows;
  final int totalUsdCents;

  const IncomeBySourceResult({required this.rows, required this.totalUsdCents});

  bool get isEmpty => rows.isEmpty;
}

/// Computed by the pure [IncomeBySourceEngine], fed by this app-layer
/// mapping from contabilidad's ledger into reportes' own
/// [TransactionView]/[EnvelopeView] (ADR-0005 — reportes never imports
/// contabilidad's `domain/`). Re-subscribes to [eventBusProvider] and
/// invalidates itself on every recorded [Transaction], mirroring
/// `spendingByEnvelopeProvider`'s reactivity pattern.
final incomeBySourceProvider =
    FutureProvider.family<IncomeBySourceResult, ReportMonth>((
      ref,
      month,
    ) async {
      final eventBus = ref.watch(eventBusProvider);
      final subscription = eventBus.stream.listen((event) {
        if (event is Transaction) ref.invalidateSelf();
      });
      ref.onDispose(subscription.cancel);
      ref.watch(catalogRevisionProvider);

      final catalog = await ref.watch(catalogRepositoryProvider.future);
      final store = await ref.watch(eventStoreProvider.future);
      final allTransactions = await store.queryLog();

      final envelopeViews = [
        for (final envelope in catalog.envelopes)
          EnvelopeView(
            id: envelope.id,
            name: envelope.name,
            role: mapEnvelopeRole(envelope.role),
          ),
      ];

      final localOffset = DateTime.now().timeZoneOffset;
      final current = _incomeFor(
        month,
        allTransactions,
        envelopeViews,
        localOffset,
      );
      final previous = _incomeFor(
        month.previousMonth,
        allTransactions,
        envelopeViews,
        localOffset,
      );

      return _buildResult(current, previous);
    });

Map<String, int> _incomeFor(
  ReportMonth month,
  List<Transaction> allTransactions,
  List<EnvelopeView> envelopes,
  Duration localOffset,
) {
  final monthTransactions =
      allTransactions
          .where(
            (tx) =>
                MonthCalendar.getReportMonth(
                  tx.metadata.occurredAt.value,
                  localOffset,
                ) ==
                month,
          )
          .toList();
  final monthIds = monthTransactions.map((tx) => tx.metadata.eventId).toSet();
  final reversals =
      allTransactions
          .where(
            (tx) =>
                tx.metadata.reverses != null &&
                monthIds.contains(tx.metadata.reverses),
          )
          .toList();

  return _engine(
    monthTransactions.map(_toView).toList(),
    reversals.map(_toView).toList(),
    envelopes,
  );
}

TransactionView _toView(Transaction tx) {
  var hasAccountPosting = false;
  final envelopePostings = <PostingView>[];
  for (final posting in tx.postings) {
    final target = posting.target;
    if (target is AccountTarget) {
      hasAccountPosting = true;
    } else if (target is EnvelopeTarget) {
      envelopePostings.add(
        PostingView(
          envelopeId: target.envelopeId,
          amountUsdCents: posting.amountUsd,
        ),
      );
    }
  }
  return TransactionView(
    id: tx.metadata.eventId,
    reverses: tx.metadata.reverses,
    hasAccountPosting: hasAccountPosting,
    envelopePostings: envelopePostings,
    source: tx.metadata.source,
  );
}

IncomeBySourceResult _buildResult(
  Map<String, int> current,
  Map<String, int> previous,
) {
  final rows = [
    for (final entry in current.entries)
      IncomeRow(
        label: entry.key,
        amountUsdCents: entry.value,
        previousAmountUsdCents: previous[entry.key] ?? 0,
      ),
  ];

  rows.sort((a, b) => b.amountUsdCents.compareTo(a.amountUsdCents));
  final totalUsdCents = rows.fold(0, (sum, row) => sum + row.amountUsdCents);

  return IncomeBySourceResult(rows: rows, totalUsdCents: totalUsdCents);
}
