class CrossCurrencyTransfer implements Exception {
  final String message;
  CrossCurrencyTransfer([
    this.message =
        'Transfer between accounts of different currencies is not allowed. Use Conversion.',
  ]);

  @override
  String toString() => 'CrossCurrencyTransfer: $message';
}

class UsdOnlyOperation implements Exception {
  final String message;
  UsdOnlyOperation([
    this.message =
        'This operation is only supported for USD accounts. Foreign currency operations belong to the conversions/P&L module.',
  ]);

  @override
  String toString() => 'UsdOnlyOperation: $message';
}

class TransactionNotFound implements Exception {
  final String message;
  TransactionNotFound(this.message);

  @override
  String toString() => 'TransactionNotFound: $message';
}

class TransactionAlreadyReversed implements Exception {
  final String message;
  TransactionAlreadyReversed(this.message);

  @override
  String toString() => 'TransactionAlreadyReversed: $message';
}

class ForeignCurrencyPositiveAdjustmentNotAllowed implements Exception {
  final String message;
  ForeignCurrencyPositiveAdjustmentNotAllowed([
    this.message =
        'Cannot positively adjust a foreign currency account. Use an income to declare the surplus with its real USD value.',
  ]);

  @override
  String toString() => 'ForeignCurrencyPositiveAdjustmentNotAllowed: $message';
}

class AdjustmentWithNoDifference implements Exception {
  final String message;
  AdjustmentWithNoDifference([
    this.message =
        'The real balance equals the projected balance. There is no difference to adjust.',
  ]);

  @override
  String toString() => 'AdjustmentWithNoDifference: $message';
}
