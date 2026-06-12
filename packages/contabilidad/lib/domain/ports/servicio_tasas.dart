import 'package:shared_kernel/shared_kernel.dart';
import 'package:decimal/decimal.dart';

abstract class ServicioTasas {
  Future<Decimal> tasaEn(String par, DomainTimestamp t);
}
