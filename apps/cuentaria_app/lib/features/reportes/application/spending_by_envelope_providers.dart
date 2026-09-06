import 'package:contabilidad/application/catalog/models/envelope.dart'
    as contabilidad;
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reportes/reportes.dart';
import 'package:shared_kernel/shared_kernel.dart';

import '../../../providers/composition_root.dart';

const _engine = SpendingByEnvelopeEngine();

/// One row of the Gasto por sobre section: an envelope's (or system row's)
/// spend this month against the same figure a full previous month ago
/// (ADR-0024 §4).
class SpendingRow {
  final EnvelopeId envelopeId;
  final String label;
  final int amountUsdCents;
  final int previousAmountUsdCents;

  const SpendingRow({
    required this.envelopeId,
    required this.label,
    required this.amountUsdCents,
    required this.previousAmountUsdCents,
  });

  /// Null when there is nothing to compare against — a brand-new envelope
  /// with no spending last month has no meaningful percentage change.
  double? get changePercent {
    if (previousAmountUsdCents == 0) return null;
    return (amountUsdCents - previousAmountUsdCents) /
        previousAmountUsdCents.abs() *
        100;
  }
}

/// The Gasto por sobre section's data (ADR-0024 §7): user envelope rows,
/// sorted highest spend first, plus the Ajustes/Diferencial realizado
/// system rows shown separately from them (ADR-0024 §2).
class SpendingByEnvelopeResult {
  final List<SpendingRow> rows;
  final SpendingRow? adjustments;
  final SpendingRow? differential;
  final int totalUsdCents;

  const SpendingByEnvelopeResult({
    required this.rows,
    required this.adjustments,
    required this.differential,
    required this.totalUsdCents,
  });

  bool get isEmpty =>
      rows.isEmpty && adjustments == null && differential == null;
}

/// Computed by the pure [SpendingByEnvelopeEngine], fed by this app-layer
/// mapping from contabilidad's ledger into reportes' own
/// [TransactionView]/[EnvelopeView] (ADR-0005 — reportes never imports
/// contabilidad's `domain/`). Re-subscribes to [eventBusProvider] and
/// invalidates itself on every recorded [Transaction], mirroring
/// `patrimonioSnapshotProvider`'s reactivity pattern.
final spendingByEnvelopeProvider =
    FutureProvider.family<SpendingByEnvelopeResult, ReportMonth>((
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

      final envelopesById = {for (final e in catalog.envelopes) e.id: e};
      final envelopeViews = [
        for (final envelope in catalog.envelopes)
          EnvelopeView(
            id: envelope.id,
            name: envelope.name,
            role: _mapRole(envelope.role),
          ),
      ];

      final localOffset = DateTime.now().timeZoneOffset;
      final current = _spendingFor(
        month,
        allTransactions,
        envelopeViews,
        localOffset,
      );
      final previous = _spendingFor(
        month.previousMonth,
        allTransactions,
        envelopeViews,
        localOffset,
      );

      return _buildResult(current, previous, envelopesById);
    });

Map<EnvelopeId, int> _spendingFor(
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
  );
}

SpendingByEnvelopeResult _buildResult(
  Map<EnvelopeId, int> current,
  Map<EnvelopeId, int> previous,
  Map<EnvelopeId, contabilidad.Envelope> envelopesById,
) {
  final rows = <SpendingRow>[];
  SpendingRow? adjustments;
  SpendingRow? differential;

  for (final entry in current.entries) {
    final envelope = envelopesById[entry.key];
    if (envelope == null) continue;

    final row = SpendingRow(
      envelopeId: entry.key,
      label: switch (envelope.role) {
        contabilidad.EnvelopeRole.adjustments => 'Ajustes',
        contabilidad.EnvelopeRole.differential => 'Diferencial realizado',
        _ => envelope.name,
      },
      amountUsdCents: entry.value,
      previousAmountUsdCents: previous[entry.key] ?? 0,
    );

    switch (envelope.role) {
      case contabilidad.EnvelopeRole.adjustments:
        adjustments = row;
      case contabilidad.EnvelopeRole.differential:
        differential = row;
      default:
        rows.add(row);
    }
  }

  rows.sort((a, b) => b.amountUsdCents.compareTo(a.amountUsdCents));
  final totalUsdCents = rows.fold(0, (sum, row) => sum + row.amountUsdCents);

  return SpendingByEnvelopeResult(
    rows: rows,
    adjustments: adjustments,
    differential: differential,
    totalUsdCents: totalUsdCents,
  );
}

EnvelopeRoleView _mapRole(contabilidad.EnvelopeRole role) => switch (role) {
  contabilidad.EnvelopeRole.none => EnvelopeRoleView.user,
  contabilidad.EnvelopeRole.stage => EnvelopeRoleView.stage,
  contabilidad.EnvelopeRole.differential => EnvelopeRoleView.differential,
  contabilidad.EnvelopeRole.adjustments => EnvelopeRoleView.adjustments,
  contabilidad.EnvelopeRole.opening => EnvelopeRoleView.opening,
};
