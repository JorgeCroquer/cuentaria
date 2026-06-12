class TargetInexistente implements Exception {
  final String message;
  TargetInexistente(this.message);

  @override
  String toString() => 'TargetInexistente: $message';
}

class MonedaIncompatible implements Exception {
  final String message;
  MonedaIncompatible(this.message);

  @override
  String toString() => 'MonedaIncompatible: $message';
}

class BorradoDeSobreDeSistemaNoPermitido implements Exception {
  final String message;
  BorradoDeSobreDeSistemaNoPermitido(this.message);

  @override
  String toString() => 'BorradoDeSobreDeSistemaNoPermitido: $message';
}
