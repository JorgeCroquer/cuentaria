import 'package:decimal/decimal.dart';
import 'package:shared_kernel/shared_kernel.dart';

import 'account_view.dart';
import 'patrimonio_snapshot.dart';
import 'rate_view.dart';

/// Pure valuation engine (ADR-0016 §5): "the parallel rate values, the BCV
/// informs". Takes only patrimonio-owned views — no Flutter, no other
/// context's domain (ADR-0005); app-layer wiring is responsible for mapping
/// contabilidad/tasas data into [AccountView]/[RateView] beforehand.
class PatrimonioEngine {
  static final _usd = CurrencyCode('USD');

  const PatrimonioEngine();

  PatrimonioSnapshot call(
    List<AccountView> accounts,
    Map<CurrencyCode, RateView> rates,
  ) {
    final groups = <CurrencyCode, _MutableGroup>{};

    for (final account in accounts) {
      if (account.isArchived) continue;

      final group = groups.putIfAbsent(
        account.currency,
        () => _MutableGroup(account.currency),
      );
      group.nativeMinorAmount += account.nativeMinorAmount;
      group.realCostUsdCents += account.realCostUsdCents;

      if (account.currency == _usd) {
        group.todayValueUsdCents += account.realCostUsdCents;
        group.bcvReferenceUsdCents += account.realCostUsdCents;
        continue;
      }

      final rate = rates[account.currency];
      final parallel = rate?.parallel;
      final bcv = rate?.bcv;

      if (parallel == null) {
        group.todayValueUsdCents += account.realCostUsdCents;
        group.hasRate = false;
      } else {
        group.todayValueUsdCents += _convert(
          account.nativeMinorAmount,
          parallel.nativePerUsd,
        );
        group.observedAt = parallel.observedAt;
      }

      group.bcvReferenceUsdCents += bcv == null
          ? account.realCostUsdCents
          : _convert(account.nativeMinorAmount, bcv.nativePerUsd);
    }

    final accountGroups = groups.values.map((g) => g.toView()).toList();

    var realCost = 0;
    var todayValue = 0;
    var bcvReference = 0;
    var hasMissingRate = false;
    for (final group in accountGroups) {
      realCost += group.realCostUsdCents;
      todayValue += group.todayValueUsdCents;
      bcvReference += group.bcvReferenceUsdCents;
      if (!group.hasRate) hasMissingRate = true;
    }

    return PatrimonioSnapshot(
      realCostUsdCents: realCost,
      todayValueUsdCents: todayValue,
      unrealizedPnlUsdCents: todayValue - realCost,
      bcvReferenceUsdCents: bcvReference,
      hasMissingRate: hasMissingRate,
      accountGroups: accountGroups,
    );
  }

  static int _convert(BigInt nativeMinorAmount, Decimal nativePerUsd) {
    return (Decimal.fromBigInt(nativeMinorAmount) / nativePerUsd)
        .round()
        .toInt();
  }
}

class _MutableGroup {
  final CurrencyCode currency;
  BigInt nativeMinorAmount = BigInt.zero;
  int realCostUsdCents = 0;
  int todayValueUsdCents = 0;
  int bcvReferenceUsdCents = 0;
  bool hasRate = true;
  DateTime? observedAt;

  _MutableGroup(this.currency);

  PatrimonioAccountGroup toView() => PatrimonioAccountGroup(
    currency: currency,
    nativeMinorAmount: nativeMinorAmount,
    realCostUsdCents: realCostUsdCents,
    todayValueUsdCents: todayValueUsdCents,
    bcvReferenceUsdCents: bcvReferenceUsdCents,
    hasRate: hasRate,
    observedAt: observedAt,
  );
}
