class TransferenciaMonedaCruzada implements Exception {
  final String message;
  TransferenciaMonedaCruzada([this.message = 'Transferencia entre cuentas de distintas monedas no permitida. Use Conversión.']);

  @override
  String toString() => 'TransferenciaMonedaCruzada: $message';
}

class OperacionSoloUSD implements Exception {
  final String message;
  OperacionSoloUSD([this.message = 'Esta operación solo está soportada para cuentas en USD. Operaciones en moneda extranjera corresponden al módulo de conversiones/P&L.']);

  @override
  String toString() => 'OperacionSoloUSD: $message';
}
