import 'package:decimal/decimal.dart';
import 'package:shared_kernel/shared_kernel.dart';

import 'debt_account_view.dart';
import 'debts_snapshot.dart';
import 'rate_view.dart';

/// Pure valuation engine (ADR-0022): "the person is only a label on a Debt
/// Account, the sign tells the story". Takes only deudas-owned views — no
/// Flutter, no other context's domain (ADR-0005); app-layer wiring is
/// responsible for mapping contabilidad/tasas data into
/// [DebtAccountView]/[RateView] beforehand.
class DebtsEngine {
  static final _usd = CurrencyCode('USD');

  const DebtsEngine();

  DebtsSnapshot call(
    List<DebtAccountView> accounts,
    Map<CurrencyCode, RateView> rates,
    DateTime now,
  ) {
    final personGroups = <String, Map<CurrencyCode, _MutableCurrencyGroup>>{};
    var bcvReferenceUsdCents = 0;

    for (final account in accounts) {
      if (account.isArchived) continue;

      final currencies = personGroups.putIfAbsent(
        account.counterpartyName,
        () => {},
      );
      final group = currencies.putIfAbsent(
        account.currency,
        () => _MutableCurrencyGroup(account.currency),
      );
      group.nativeMinorAmount += account.nativeMinorAmount;
      group.realCostUsdCents += account.realCostUsdCents;

      if (account.currency == _usd) {
        group.todayValueUsdCents += account.realCostUsdCents;
        bcvReferenceUsdCents += account.realCostUsdCents;
        continue;
      }

      final rate = rates[account.currency];

      final parallel = rate?.parallel;
      if (parallel == null) {
        group.todayValueUsdCents += account.realCostUsdCents;
        group.hasRate = false;
      } else {
        group.todayValueUsdCents += _convert(
          account.nativeMinorAmount,
          parallel.nativePerUsd,
        );
        group.parallelRate = parallel;
      }

      final bcv = rate?.bcv;
      if (bcv == null) {
        bcvReferenceUsdCents += account.realCostUsdCents;
      } else {
        bcvReferenceUsdCents += _convert(
          account.nativeMinorAmount,
          bcv.nativePerUsd,
        );
      }
    }

    final personas =
        personGroups.entries.map((entry) {
          final currencies = entry.value.values.map((g) => g.toView()).toList();

          var netoUsd = 0;
          var hasTasa = true;
          for (final leg in currencies) {
            netoUsd += leg.todayValueUsdCents;
            if (!leg.hasRate) hasTasa = false;
          }

          return PersonDebts(
            personName: entry.key,
            currencies: currencies,
            netoUsdCents: netoUsd,
            hasTasa: hasTasa,
          );
        }).toList();

    var globalNeto = 0;
    for (final persona in personas) {
      globalNeto += persona.netoUsdCents;
    }

    return DebtsSnapshot(
      personas: personas,
      globalNetoUsdCents: globalNeto,
      bcvReferenceUsdCents: bcvReferenceUsdCents,
      calculatedAt: now,
    );
  }

  static int _convert(BigInt nativeMinorAmount, Decimal nativePerUsd) {
    return (Decimal.fromBigInt(nativeMinorAmount) / nativePerUsd)
        .round()
        .toInt();
  }
}

class _MutableCurrencyGroup {
  final CurrencyCode currency;
  BigInt nativeMinorAmount = BigInt.zero;
  int realCostUsdCents = 0;
  int todayValueUsdCents = 0;
  bool hasRate = true;
  RateObservationView? parallelRate;

  _MutableCurrencyGroup(this.currency);

  PersonCurrencyDebt toView() => PersonCurrencyDebt(
    currency: currency,
    nativeMinorAmount: nativeMinorAmount,
    realCostUsdCents: realCostUsdCents,
    todayValueUsdCents: todayValueUsdCents,
    hasRate: hasRate,
    parallelRate: parallelRate,
  );
}
