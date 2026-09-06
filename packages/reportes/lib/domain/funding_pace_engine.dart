import 'package:equatable/equatable.dart';
import 'package:shared_kernel/shared_kernel.dart';

import 'funding_envelope_view.dart';
import 'funding_target_view.dart';
import 'report_month.dart';
import 'transaction_view.dart';

/// Where an Envelope's monthly contribution stands against what a
/// [GoalLineView.dueDate] requires (#263). Only computed with a due date —
/// [FundingPaceRow.status] is null without one.
enum FundingPaceStatus { onPace, behind, goalReached }

/// One row of the Aportes a metas section: an Envelope with a Funding
/// Target, how much it was contributed this Report Month, and — with a
/// [GoalLineView.dueDate] — what it takes per month to arrive on time.
class FundingPaceRow extends Equatable {
  final EnvelopeId envelopeId;
  final String name;
  final int contributedThisMonthUsdCents;
  final int? requiredPerMonthUsdCents;
  final FundingPaceStatus? status;

  const FundingPaceRow({
    required this.envelopeId,
    required this.name,
    required this.contributedThisMonthUsdCents,
    required this.requiredPerMonthUsdCents,
    required this.status,
  });

  @override
  List<Object?> get props => [
    envelopeId,
    name,
    contributedThisMonthUsdCents,
    requiredPerMonthUsdCents,
    status,
  ];
}

/// Pure funding-pace motor (#263): today's progress already lives in
/// Patrimonio (ADR-0015) and is not repeated here — this only looks at the
/// Report Month's contributions. Only inflows (positive `amount_usd`
/// postings) into the Envelope count as an aporte; an expense leaving it is
/// never a negative aporte. Without a [GoalLineView.dueDate] (or for a
/// [CapView], which never has one), only [FundingPaceRow.contributedThisMonthUsdCents]
/// is meaningful — required/status stay null. A balance that already meets
/// the goal is always `goalReached`, regardless of this month's aporte.
///
/// [reversals] follow the same rule as `SpendingByEnvelopeEngine`: a
/// Reversal subtracts its original's contribution from this month's total
/// (ADR-0024 §3) — app-layer wiring passes only Reversals of *later* months
/// whose `reverses` points into [transactions].
class FundingPaceEngine {
  const FundingPaceEngine();

  List<FundingPaceRow> call(
    List<TransactionView> transactions,
    List<TransactionView> reversals,
    List<FundingEnvelopeView> envelopes,
    ReportMonth reportMonth,
  ) {
    final contributed = <EnvelopeId, int>{};

    void apply(TransactionView tx, int sign) {
      for (final posting in tx.envelopePostings) {
        if (posting.amountUsdCents <= 0) continue;
        contributed.update(
          posting.envelopeId,
          (v) => v + posting.amountUsdCents * sign,
          ifAbsent: () => posting.amountUsdCents * sign,
        );
      }
    }

    for (final tx in transactions) {
      apply(tx, 1);
    }

    final byId = {for (final tx in transactions) tx.id: tx};
    for (final reversal in reversals) {
      final original = byId[reversal.reverses];
      if (original == null) continue;
      apply(original, -1);
    }

    final rows = <FundingPaceRow>[];
    for (final envelope in envelopes) {
      final row = _rowFor(envelope, contributed[envelope.id] ?? 0, reportMonth);
      if (row != null) rows.add(row);
    }
    return rows;
  }

  static FundingPaceRow? _rowFor(
    FundingEnvelopeView envelope,
    int contributedThisMonth,
    ReportMonth reportMonth,
  ) {
    final target = envelope.target;
    final amountUsd = switch (target) {
      NoTargetView() => 0,
      CapView(:final amountUsd) => amountUsd,
      GoalLineView(:final amountUsd) => amountUsd,
    };
    if (amountUsd <= 0) return null;

    final dueDate = target is GoalLineView ? target.dueDate : null;
    if (dueDate == null) {
      return FundingPaceRow(
        envelopeId: envelope.id,
        name: envelope.name,
        contributedThisMonthUsdCents: contributedThisMonth,
        requiredPerMonthUsdCents: null,
        status: null,
      );
    }

    if (envelope.balanceUsdCents >= amountUsd) {
      return FundingPaceRow(
        envelopeId: envelope.id,
        name: envelope.name,
        contributedThisMonthUsdCents: contributedThisMonth,
        requiredPerMonthUsdCents: 0,
        status: FundingPaceStatus.goalReached,
      );
    }

    final monthsRemaining = _monthsRemaining(reportMonth, dueDate);
    final requiredPerMonth = _ceilDiv(
      amountUsd - envelope.balanceUsdCents,
      monthsRemaining,
    );

    return FundingPaceRow(
      envelopeId: envelope.id,
      name: envelope.name,
      contributedThisMonthUsdCents: contributedThisMonth,
      requiredPerMonthUsdCents: requiredPerMonth,
      status:
          contributedThisMonth >= requiredPerMonth
              ? FundingPaceStatus.onPace
              : FundingPaceStatus.behind,
    );
  }

  static int _monthsRemaining(ReportMonth reportMonth, DateTime dueDate) {
    final diff =
        (dueDate.year * 12 + dueDate.month) -
        (reportMonth.year * 12 + reportMonth.month);
    return diff < 1 ? 1 : diff;
  }

  static int _ceilDiv(int a, int b) => (a + b - 1) ~/ b;
}
