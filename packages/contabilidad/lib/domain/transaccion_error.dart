abstract class TransaccionError implements Exception {
  final String message;
  TransaccionError(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

class TransaccionVacia extends TransaccionError {
  TransaccionVacia() : super('La transacción debe tener al menos un posting.');
}

class TransaccionNoBalanceada extends TransaccionError {
  TransaccionNoBalanceada()
    : super('La transacción no está balanceada entre cuentas y sobres.');
}
