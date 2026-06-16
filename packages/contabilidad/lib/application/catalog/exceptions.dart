class TargetNotFound implements Exception {
  final String message;
  TargetNotFound(this.message);

  @override
  String toString() => 'TargetNotFound: $message';
}

class IncompatibleCurrency implements Exception {
  final String message;
  IncompatibleCurrency(this.message);

  @override
  String toString() => 'IncompatibleCurrency: $message';
}

class SystemEnvelopeDeletionNotAllowed implements Exception {
  final String message;
  SystemEnvelopeDeletionNotAllowed(this.message);

  @override
  String toString() => 'SystemEnvelopeDeletionNotAllowed: $message';
}
