/// Pure validators for the create/edit Account form (#94), kept free of
/// Flutter so they're directly unit-testable.
library;

import 'package:decimal/decimal.dart';

const _maxNameLength = 50;

String? validateAccountName(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 'El nombre es obligatorio.';
  if (trimmed.length > _maxNameLength) {
    return 'El nombre debe tener $_maxNameLength caracteres o menos.';
  }
  return null;
}

/// Opening balance is optional (empty means "no opening balance"). Accepts
/// decimals with comma or dot (25,50 / 25.50) up to 2 places — the ledger
/// still stores int minor units; [parseOpeningBalanceMinorUnits] converts.
String? validateOpeningBalance(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;

  final parsed = Decimal.tryParse(trimmed.replaceAll(',', '.'));
  if (parsed == null) return 'El saldo inicial debe ser un número.';
  if (parsed < Decimal.zero) return 'El saldo inicial no puede ser negativo.';
  if (parsed.scale > 2) {
    return 'El saldo inicial acepta hasta 2 decimales.';
  }
  return null;
}

/// The minor-unit (cents) value of a valid opening-balance text, or null
/// when empty/invalid/zero. Single place where "25,50" becomes 2550.
int? parseOpeningBalanceMinorUnits(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final parsed = Decimal.tryParse(trimmed.replaceAll(',', '.'));
  if (parsed == null || parsed <= Decimal.zero || parsed.scale > 2) {
    return null;
  }
  return (parsed * Decimal.fromInt(100)).toBigInt().toInt();
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
    return 'La tasa de cambio es obligatoria para cuentas en $currency.';
  }

  final rate = Decimal.tryParse(trimmedRate);
  if (rate == null || rate <= Decimal.zero) {
    return 'La tasa de cambio debe ser un número positivo.';
  }
  return null;
}
