import 'package:contabilidad/application/catalog/models/funding_target.dart'
    as contabilidad;
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reportes/reportes.dart';

import '../../../providers/composition_root.dart';

const _engine = FundingPaceEngine();
const _monthsOfHistory = 12;

/// One envelope's Aportes a metas row plus its last 12 months of aportes,
/// oldest first, for the mini `fl_chart` bar (#263).
class FundingPaceEnvelopeResult {
  final FundingPaceRow row;
  final List<int> monthlyContributionsUsdCents;

  const FundingPaceEnvelopeResult({
    required this.row,
    required this.monthlyContributionsUsdCents,
  });
}

class FundingPaceSectionResult {
  final List<FundingPaceEnvelopeResult> rows;

  const FundingPaceSectionResult({required this.rows});

  bool get isEmpty => rows.isEmpty;
}

/// Computed by the pure [FundingPaceEngine], fed by this app-layer mapping
/// from contabilidad's catalog/ledger into reportes' own
/// [FundingEnvelopeView]/[TransactionView] (ADR-0005 — reportes never
/// imports contabilidad's `domain/`). The current balance comes straight
/// from [ledgerProjectionsProvider] — today's cascade balance, the same one
/// Patrimonio already shows, never a month-end recomputation. The 12-month
/// history is 12 reproductions of the pure engine (ADR-0024 §5), one per
/// Report Month. Re-subscribes to [eventBusProvider], mirroring
/// `spendingByEnvelopeProvider`'s reactivity pattern.
final fundingPaceProvider =
    FutureProvider.family<FundingPaceSectionResult, ReportMonth>((
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
      final projections = ref.watch(ledgerProjectionsProvider);
      final allTransactions = await store.queryLog();

      final envelopes = [
        for (final envelope in catalog.envelopes)
          if (!envelope.isArchived && envelope.target is! contabilidad.NoTarget)
            FundingEnvelopeView(
              id: envelope.id,
              name: envelope.name,
              balanceUsdCents: projections.envelopeUsdBalance(envelope.id),
              target: _mapTarget(envelope.target),
            ),
      ];
      if (envelopes.isEmpty) {
        return const FundingPaceSectionResult(rows: []);
      }

      final localOffset = DateTime.now().timeZoneOffset;
      final months = List.generate(
        _monthsOfHistory,
        (i) => _monthsBefore(month, _monthsOfHistory - 1 - i),
      );

      final rowsByMonth = <ReportMonth, List<FundingPaceRow>>{
        for (final reportMonth in months)
          reportMonth: _rowsFor(
            reportMonth,
            allTransactions,
            envelopes,
            localOffset,
          ),
      };

      final currentRows = rowsByMonth[month]!;
      final rows = [
        for (final row in currentRows)
          FundingPaceEnvelopeResult(
            row: row,
            monthlyContributionsUsdCents: [
              for (final reportMonth in months)
                rowsByMonth[reportMonth]!
                    .firstWhere((r) => r.envelopeId == row.envelopeId)
                    .contributedThisMonthUsdCents,
            ],
          ),
      ];

      return FundingPaceSectionResult(rows: rows);
    });

List<FundingPaceRow> _rowsFor(
  ReportMonth month,
  List<Transaction> allTransactions,
  List<FundingEnvelopeView> envelopes,
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
    month,
  );
}

TransactionView _toView(Transaction tx) {
  final envelopePostings = <PostingView>[];
  for (final posting in tx.postings) {
    final target = posting.target;
    if (target is EnvelopeTarget) {
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
    hasAccountPosting: tx.postings.any((p) => p.target is AccountTarget),
    envelopePostings: envelopePostings,
  );
}

FundingTargetView _mapTarget(contabilidad.FundingTarget target) =>
    switch (target) {
      contabilidad.NoTarget() => const NoTargetView(),
      contabilidad.Cap(:final amountUsd) => CapView(amountUsd: amountUsd),
      contabilidad.GoalLine(:final amountUsd, :final dueDate) => GoalLineView(
        amountUsd: amountUsd,
        dueDate: dueDate,
      ),
    };

ReportMonth _monthsBefore(ReportMonth month, int count) {
  var result = month;
  for (var i = 0; i < count; i++) {
    result = result.previousMonth;
  }
  return result;
}
