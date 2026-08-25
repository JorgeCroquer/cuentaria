import 'package:equatable/equatable.dart';
import 'package:shared_kernel/shared_kernel.dart';

import 'rate_view.dart';

/// One currency leg of a person's debt (ADR-0022 §3: "one person owing in
/// two currencies = two Debt Accounts, grouped under the person"):
/// [nativeMinorAmount] and [realCostUsdCents] sum every non-archived Debt
/// Account this person holds in [currency]; [todayValueUsdCents] falls back
/// to real cost with [hasRate] false when no parallel observation exists —
/// never a silent 1:1 (S2-8). [parallelRate] carries the actual observation
/// used so the UI can announce it.
class PersonCurrencyDebt extends Equatable {
  final CurrencyCode currency;
  final BigInt nativeMinorAmount;
  final int realCostUsdCents;
  final int todayValueUsdCents;
  final bool hasRate;
  final RateObservationView? parallelRate;

  const PersonCurrencyDebt({
    required this.currency,
    required this.nativeMinorAmount,
    required this.realCostUsdCents,
    required this.todayValueUsdCents,
    required this.hasRate,
    this.parallelRate,
  });

  @override
  List<Object?> get props => [
    currency,
    nativeMinorAmount,
    realCostUsdCents,
    todayValueUsdCents,
    hasRate,
    parallelRate,
  ];
}

/// One counterparty's debt (ADR-0022 §1: the person is only a label on its
/// Debt Accounts, never a domain entity). [netoUsdCents] combines every
/// currency this person holds, valued at today's parallel rate; the sign
/// travels as-is (negative = the user owes this person). [hasTasa] is false
/// when any currency leg lacked a parallel observation and fell back to
/// frozen cost — the "sin tasa" flag S2-8 requires to be announceable.
class PersonDebts extends Equatable {
  final String personName;
  final List<PersonCurrencyDebt> currencies;
  final int netoUsdCents;
  final bool hasTasa;

  const PersonDebts({
    required this.personName,
    required this.currencies,
    required this.netoUsdCents,
    required this.hasTasa,
  });

  @override
  List<Object?> get props => [personName, currencies, netoUsdCents, hasTasa];
}

/// The Deudas engine's output: every counterparty's net debt and the global
/// net (signed sum of all personas — positive means net creditor).
/// Archived Debt Accounts never enter this projection (ADR-0022 §1).
class DebtsSnapshot extends Equatable {
  final List<PersonDebts> personas;
  final int globalNetoUsdCents;
  final DateTime calculatedAt;

  const DebtsSnapshot({
    required this.personas,
    required this.globalNetoUsdCents,
    required this.calculatedAt,
  });

  @override
  List<Object?> get props => [personas, globalNetoUsdCents, calculatedAt];
}
