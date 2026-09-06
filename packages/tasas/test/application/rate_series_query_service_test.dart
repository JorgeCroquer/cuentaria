import 'package:decimal/decimal.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/application/rate_series_query_service.dart';
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
  group('RateSeriesQueryService', () {
    final ves = CurrencyCode('VES');
    final eur = CurrencyCode('EUR');

    test('currenciesWithObservations lists only currencies with at least '
        'one observation, in first-seen order', () async {
      final series = InMemoryRateSeries();
      await series.append(
        _obs(
          currency: 'VES',
          rate: '900.00',
          observedAt: DateTime.utc(2026, 8, 1),
          source: 'manual:paralelo',
        ),
      );
      await series.append(
        _obs(
          currency: 'EUR',
          rate: '38.00',
          observedAt: DateTime.utc(2026, 8, 2),
          source: 'manual:paralelo',
        ),
      );

      final service = RateSeriesQueryService(series);

      expect(await service.currenciesWithObservations(), [ves, eur]);
    });

    test('currenciesWithObservations is empty when the series has never '
        'recorded anything', () async {
      final service = RateSeriesQueryService(InMemoryRateSeries());

      expect(await service.currenciesWithObservations(), isEmpty);
    });

    test('observationsFor scopes to the given currency and drops '
        'observations older than 12 months back from now', () async {
      final series = InMemoryRateSeries();
      final now = DateTime.utc(2026, 9, 6, 10);
      final withinWindow = _obs(
        rate: '900.00',
        observedAt: DateTime.utc(2026, 8, 5),
        source: 'manual:paralelo',
      );
      final tooOld = _obs(
        rate: '600.00',
        observedAt: DateTime.utc(2025, 8, 1),
        source: 'manual:paralelo',
      );
      final otherCurrency = _obs(
        currency: 'EUR',
        rate: '38.00',
        observedAt: DateTime.utc(2026, 8, 5),
        source: 'manual:paralelo',
      );
      await series.append(withinWindow);
      await series.append(tooOld);
      await series.append(otherCurrency);

      final service = RateSeriesQueryService(series);
      final observations = await service.observationsFor(ves, asOf: now);

      expect(observations, [withinWindow]);
    });

    test('observationsFor returns observations oldest first', () async {
      final series = InMemoryRateSeries();
      final now = DateTime.utc(2026, 9, 6, 10);
      final earlier = _obs(
        rate: '800.00',
        observedAt: DateTime.utc(2026, 8, 1),
        source: 'manual:paralelo',
      );
      final later = _obs(
        rate: '900.00',
        observedAt: DateTime.utc(2026, 8, 20),
        source: 'manual:paralelo',
      );
      await series.append(later);
      await series.append(earlier);

      final service = RateSeriesQueryService(series);
      final observations = await service.observationsFor(ves, asOf: now);

      expect(observations, [earlier, later]);
    });
  });
}
