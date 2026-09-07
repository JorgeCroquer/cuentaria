import 'envelope_view.dart';
import 'transaction_view.dart';

/// Pure income-by-source motor (ADR-0024 §1-§3), the sibling of
/// [SpendingByEnvelopeEngine]: flow is read from the **role of the Envelope
/// touched**, never the event type. A posting that enters an Envelope (a
/// non-negative `amount_usd`) is ingreso, grouped by the transaction's
/// free-form `source` label — landing in Stage, like every quick-add Income
/// does, still counts. Only Apertura and Ajustes are excluded outright: they
/// are not money from outside. A transaction with no Account-dimension
/// posting (a Distribution: only Envelope-to-Envelope legs, "own pockets")
/// never contributes, even though its incoming leg may land in a role=user
/// Envelope just like an Income does.
///
/// [reversals] are the Reversals of *later* months whose `reverses` points
/// to a transaction in [transactions] — app-layer wiring is responsible for
/// that filtering. A matched reversal subtracts its original's contribution
/// from this month's totals (ADR-0024 §3): the history of the month being
/// corrected never moves.
class IncomeBySourceEngine {
  static const _sinFuente = 'Sin fuente';

  const IncomeBySourceEngine();

  Map<String, int> call(
    List<TransactionView> transactions,
    List<TransactionView> reversals,
    List<EnvelopeView> envelopes,
  ) {
    final envelopesById = {for (final e in envelopes) e.id: e};
    final totals = <String, int>{};

    void apply(TransactionView tx, int sign) {
      if (!tx.hasAccountPosting) return;

      var amount = 0;
      for (final posting in tx.envelopePostings) {
        final envelope = envelopesById[posting.envelopeId];
        if (envelope == null) continue;
        if (envelope.role == EnvelopeRoleView.opening) continue;
        if (envelope.role == EnvelopeRoleView.adjustments) continue;
        if (posting.amountUsdCents < 0) continue;
        amount += posting.amountUsdCents;
      }
      if (amount == 0) return;

      final source =
          (tx.source == null || tx.source!.isEmpty) ? _sinFuente : tx.source!;
      totals.update(
        source,
        (v) => v + amount * sign,
        ifAbsent: () => amount * sign,
      );
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
