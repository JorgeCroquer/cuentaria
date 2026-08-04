/// Pure validators for the create/edit Account form (#94), kept free of
/// Flutter so they're directly unit-testable.
library;

import 'package:decimal/decimal.dart';

const _maxNameLength = 50;

String? validateAccountName(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 'Name is required.';
  if (trimmed.length > _maxNameLength) {
    return 'Name must be $_maxNameLength characters or fewer.';
  }
  return null;
}

/// Opening balance is optional (empty means "no opening balance") and, per
/// the "money is always int minor units" rule, must be a whole number.
String? validateOpeningBalance(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;

  final parsed = int.tryParse(trimmed);
  if (parsed == null) return 'Opening balance must be a whole number.';
  if (parsed < 0) return 'Opening balance cannot be negative.';
  return null;
}

/// The exchange rate (native-per-USD) is required whenever the account's
/// currency isn't USD — with an opening balance it freezes the real cost of
/// the opening fact (ADR-0006); without one, it's the first parallel-rate
/// observation the app needs to price a Bs expense (#112), asked for once,
/// during account creation, instead of surfacing as a later error.
String? validateOpeningBalanceRate({
  required String currency,
  required String rateText,
}) {
  if (currency == 'USD') return null;

  final trimmedRate = rateText.trim();
  if (trimmedRate.isEmpty) {
    return 'Exchange rate is required for $currency accounts.';
  }

  final rate = Decimal.tryParse(trimmedRate);
  if (rate == null || rate <= Decimal.zero) {
    return 'Exchange rate must be a positive number.';
  }
  return null;
}
