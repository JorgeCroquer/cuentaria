import 'package:shared_kernel/shared_kernel.dart';
import 'package:decimal/decimal.dart';
import '../domain/ports/rate_service.dart';

class InMemoryRateService implements RateService {
  final Map<String, Decimal> _rates = {};

  void setRate(String pair, Decimal rate) => _rates[pair] = rate;

  @override
  Future<Decimal> rateAt(String pair, DomainTimestamp t) async {
    return _rates[pair] ?? Decimal.one;
  }
}
