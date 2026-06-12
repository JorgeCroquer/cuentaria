import 'package:shared_kernel/shared_kernel.dart';
import 'package:decimal/decimal.dart';
import '../domain/ports/servicio_tasas.dart';

class InMemoryServicioTasas implements ServicioTasas {
  final Map<String, Decimal> _rates = {};

  void setRate(String par, Decimal rate) => _rates[par] = rate;

  @override
  Future<Decimal> tasaEn(String par, DomainTimestamp t) async {
    return _rates[par] ?? Decimal.one;
  }
}
