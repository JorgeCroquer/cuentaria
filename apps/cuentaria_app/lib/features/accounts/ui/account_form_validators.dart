/// Pure validators for the create/edit Account form (#94), kept free of
/// Flutter so they're directly unit-testable.
library;

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
