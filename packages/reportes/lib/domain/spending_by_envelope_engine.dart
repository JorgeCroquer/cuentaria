import 'package:shared_kernel/shared_kernel.dart';

import 'envelope_view.dart';
import 'transaction_view.dart';

/// Pure spending-by-envelope motor (ADR-0024 §1-§3): flow is read from the
/// **role of the Envelope touched**, never the event type. A posting into a
/// user Envelope (`EnvelopeRoleView.user`) that leaves it (a negative
/// `amount_usd`) is gasto; a posting into a System Envelope has its own
/// row — Ajustes or Diferencial realizado — carrying its raw signed amount;
/// Stage and Apertura are excluded outright, they are not flow. A
/// transaction with no Account-dimension posting (a Distribution: only
/// Envelope-to-Envelope legs, "own pockets", ADR-0024 §2) never contributes,
/// even though its legs touch role=user Envelopes just like an Expense does.
///
/// [reversals] are the Reversals of *later* months whose `reverses` points
/// to a transaction in [transactions] — app-layer wiring is responsible for
/// that filtering (a same-month reversal is simply part of [transactions]
/// already and nets out on its own). A matched reversal subtracts its
/// original's contribution from this month's totals (ADR-0024 §3): the
/// history of the month being corrected never moves.
class SpendingByEnvelopeEngine {
  const SpendingByEnvelopeEngine();

  Map<EnvelopeId, int> call(
    List<TransactionView> transactions,
    List<TransactionView> reversals,
    List<EnvelopeView> envelopes,
  ) {
    final envelopesById = {for (final e in envelopes) e.id: e};
    final totals = <EnvelopeId, int>{};

    void apply(TransactionView tx, int sign) {
      if (!tx.hasAccountPosting) return;

      for (final posting in tx.envelopePostings) {
        final envelope = envelopesById[posting.envelopeId];
        if (envelope == null) continue;

        switch (envelope.role) {
          case EnvelopeRoleView.user:
            if (posting.amountUsdCents >= 0) continue;
            totals.update(
              envelope.id,
              (v) => v - posting.amountUsdCents * sign,
              ifAbsent: () => -posting.amountUsdCents * sign,
            );
          case EnvelopeRoleView.adjustments:
          case EnvelopeRoleView.differential:
            totals.update(
              envelope.id,
              (v) => v + posting.amountUsdCents * sign,
              ifAbsent: () => posting.amountUsdCents * sign,
            );
          case EnvelopeRoleView.stage:
          case EnvelopeRoleView.opening:
            continue;
        }
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

    totals.removeWhere((_, amount) => amount == 0);
    return totals;
  }
}
