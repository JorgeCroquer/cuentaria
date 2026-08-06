import 'package:decimal/decimal.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/application/rate_resolution_service.dart';
import 'package:tasas/domain/rate_observation.dart';
import 'package:tasas/infrastructure/in_memory/in_memory_rate_series.dart';
import 'package:test/test.dart';

RateObservation _obs({
  String currency = 'VES',
  required String rate,
  required DateTime observedAt,
  required String source,
}) => RateObservation(
  currency: CurrencyCode(currency),
  nativePerUsd: Decimal.parse(rate),
  observedAt: observedAt,
  source: source,
);

void main() {
  group('RateResolutionService', () {
    final ves = CurrencyCode('VES');

    test('chains RateSeries.candidatesFor into resolve()', () async {
      final series = InMemoryRateSeries();
      final today = DateTime.utc(2026, 8, 5, 10);
      await series.append(
        _obs(rate: '900.00', observedAt: today, source: 'manual:paralelo'),
      );
      await series.append(
        _obs(rate: '845.88', observedAt: today, source: 'binancep2p:ask'),
      );

      final service = RateResolutionService(series);
      final resolution = await service(ves, asOf: today);

      expect(resolution?.source, 'manual:paralelo');
      expect(resolution?.nativePerUsd, Decimal.parse('900.00'));
    });

    test('defaults asOf to now when omitted', () async {
      final series = InMemoryRateSeries();
      await series.append(
        _obs(
          rate: '845.88',
          observedAt: DateTime.now().toUtc(),
          source: 'binancep2p:ask',
        ),
      );

      final service = RateResolutionService(series);
      final resolution = await service(ves);

      expect(resolution?.source, 'binancep2p:ask');
    });

    test('returns null when no candidate is eligible', () async {
      final series = InMemoryRateSeries();
      final service = RateResolutionService(series);

      expect(await service(ves), isNull);
    });
  });
}
