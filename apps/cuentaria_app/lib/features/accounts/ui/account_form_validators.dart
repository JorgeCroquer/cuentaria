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

/// The opening-balance exchange rate (native-per-USD) is required whenever
/// the account's currency isn't USD and it carries a non-zero opening
/// balance — ADR-0006 freezes the real cost at the rate of the opening fact,
/// so there is no fallback rate to infer it from.
String? validateOpeningBalanceRate({
  required String currency,
  required String openingBalanceText,
  required String rateText,
}) {
  final openingBalance = int.tryParse(openingBalanceText.trim()) ?? 0;
  if (currency == 'USD' || openingBalance == 0) return null;

  final trimmedRate = rateText.trim();
  if (trimmedRate.isEmpty) {
    return 'Exchange rate is required for opening balance in $currency.';
  }

  final rate = Decimal.tryParse(trimmedRate);
  if (rate == null || rate <= Decimal.zero) {
    return 'Exchange rate must be a positive number.';
  }
  return null;
}
