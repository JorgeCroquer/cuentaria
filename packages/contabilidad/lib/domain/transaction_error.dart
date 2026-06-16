abstract class TransactionError implements Exception {
  final String message;
  TransactionError(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

class EmptyTransaction extends TransactionError {
  EmptyTransaction() : super('Transaction must have at least one posting.');
}

class UnbalancedTransaction extends TransactionError {
  UnbalancedTransaction()
    : super('Transaction is not balanced between accounts and envelopes.');
}
