import 'envelope_view.dart';
import 'exchange_differential_point.dart';
import 'patrimonio_point.dart';
import 'spending_by_envelope_engine.dart';
import 'transaction_view.dart';

const _spendingEngine = SpendingByEnvelopeEngine();

/// Pure Diferencial cambiario motor (#264, ADR-0024 §7): realizado is
/// extracted from [SpendingByEnvelopeEngine]'s own totals rather than
/// resummed — the Sobre de Sistema Diferencial's flow is already correct
/// there (#259), including reversal handling. No realizado is [point]'s
/// overlay gap: market value minus real cost, both of which are that same
/// month's Net Worth Point (#260) — an honest blank whenever it has no
/// market value.
class ExchangeDifferentialEngine {
  const ExchangeDifferentialEngine();

  ExchangeDifferentialPoint call(
    List<TransactionView> transactions,
    List<TransactionView> reversals,
    List<EnvelopeView> envelopes,
    PatrimonioPoint point,
  ) {
    final totals = _spendingEngine(transactions, reversals, envelopes);
    final envelopesById = {for (final e in envelopes) e.id: e};

    final realizadoUsdCents = totals.entries
        .where(
          (entry) =>
              envelopesById[entry.key]?.role == EnvelopeRoleView.differential,
        )
        .fold(0, (sum, entry) => sum + entry.value);

    final marketValue = point.marketValueUsdCents;
    final noRealizadoUsdCents =
        marketValue == null ? null : marketValue - point.realCostUsdCents;

    return ExchangeDifferentialPoint(
      month: point.month,
      realizadoUsdCents: realizadoUsdCents,
      noRealizadoUsdCents: noRealizadoUsdCents,
    );
  }
}
