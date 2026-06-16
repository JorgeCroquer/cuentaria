import 'package:shared_kernel/shared_kernel.dart';
import 'package:decimal/decimal.dart';

abstract class RateService {
  Future<Decimal> rateAt(String pair, DomainTimestamp t);
}
