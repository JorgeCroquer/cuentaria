import 'package:decimal/decimal.dart';

/// Decision made from a reconciliation delta (ADR-0019): the size of the
/// delta once converted to USD decides what happens to it, never its sign.
sealed class ReconciliationOutcome {
  const ReconciliationOutcome();
}

/// The real balance matches the projected one — nothing to post.
class NothingToReconcile extends ReconciliationOutcome {
  const NothingToReconcile();
}

/// Delta within the Tolerance: absorbed against the system Adjustments
/// envelope in one touch.
class Absorb extends ReconciliationOutcome {
  final BigInt deltaNative;
  final int deltaUsd;

  const Absorb({required this.deltaNative, required this.deltaUsd});
}

/// Surplus above the Tolerance: the app offers to register it as an Income
/// instead of absorbing it (ADR-0019 §2).
class RouteToIncome extends ReconciliationOutcome {
  final BigInt deltaNative;
  final int suggestedUsd;

  const RouteToIncome({required this.deltaNative, required this.suggestedUsd});
}

/// Shortage above the Tolerance: the app offers to register it as an
/// Expense instead of absorbing it.
class RouteToExpense extends ReconciliationOutcome {
  final BigInt deltaNative;
  final int suggestedUsd;

  const RouteToExpense({required this.deltaNative, required this.suggestedUsd});
}

/// $1.00, the single constant Tolerance (ADR-0019 §3) — no per-account
/// configuration.
const defaultReconciliationToleranceUsdCents = 100;

/// Pure decision function (ADR-0019): no I/O, no ports. [deltaNative] is the
/// real balance minus the projected one, in the account's native minor
/// units; [rate] is native units per USD (pass [Decimal.one] for a USD
/// account, since its native minor units already are USD cents). The delta
/// is converted to USD with a single rounding, purely to size it against
/// [toleranceUsdCents] — how the delta eventually gets valued for posting is
/// a separate concern the caller owns.
ReconciliationOutcome planReconciliation({
  required BigInt deltaNative,
  required Decimal rate,
  int toleranceUsdCents = defaultReconciliationToleranceUsdCents,
}) {
  if (deltaNative == BigInt.zero) {
    return const NothingToReconcile();
  }

  final deltaUsd = (Decimal.fromBigInt(deltaNative) / rate).round().toInt();

  if (deltaUsd.abs() <= toleranceUsdCents) {
    return Absorb(deltaNative: deltaNative, deltaUsd: deltaUsd);
  }

  return deltaUsd > 0
      ? RouteToIncome(deltaNative: deltaNative, suggestedUsd: deltaUsd)
      : RouteToExpense(deltaNative: deltaNative, suggestedUsd: deltaUsd);
}
