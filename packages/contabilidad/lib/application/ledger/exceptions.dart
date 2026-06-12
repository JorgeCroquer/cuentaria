class TransferenciaMonedaCruzada implements Exception {
  final String message;
  TransferenciaMonedaCruzada([
    this.message =
        'Transferencia entre cuentas de distintas monedas no permitida. Use Conversión.',
  ]);

  @override
  String toString() => 'TransferenciaMonedaCruzada: $message';
}

class OperacionSoloUSD implements Exception {
  final String message;
  OperacionSoloUSD([
    this.message =
        'Esta operación solo está soportada para cuentas en USD. Operaciones en moneda extranjera corresponden al módulo de conversiones/P&L.',
  ]);

  @override
  String toString() => 'OperacionSoloUSD: $message';
}

class SaldoInsuficiente implements Exception {
  final String message;
  SaldoInsuficiente(this.message);

  @override
  String toString() => 'SaldoInsuficiente: $message';
}

class TransaccionNoEncontrada implements Exception {
  final String message;
  TransaccionNoEncontrada(this.message);

  @override
  String toString() => 'TransaccionNoEncontrada: $message';
}

class TransaccionYaReversada implements Exception {
  final String message;
  TransaccionYaReversada(this.message);

  @override
  String toString() => 'TransaccionYaReversada: $message';
}

class AjustePositivoMonedaExtranjeraNoPermitido implements Exception {
  final String message;
  AjustePositivoMonedaExtranjeraNoPermitido([
    this.message =
        'No se puede ajustar positivamente una cuenta en moneda extranjera. Use un ingreso para declarar el excedente con su valor real en USD.',
  ]);

  @override
  String toString() => 'AjustePositivoMonedaExtranjeraNoPermitido: $message';
}

class AjusteSinDiferencia implements Exception {
  final String message;
  AjusteSinDiferencia([
    this.message =
        'El saldo real es igual al saldo proyectado. No hay diferencia que ajustar.',
  ]);

  @override
  String toString() => 'AjusteSinDiferencia: $message';
}
