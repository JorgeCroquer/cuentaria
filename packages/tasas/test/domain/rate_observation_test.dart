import 'package:decimal/decimal.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/domain/rate_observation.dart';
import 'package:test/test.dart';

void main() {
  group('RateObservation', () {
    test('holds currency, rate, timestamp and source', () {
      final observedAt = DateTime.utc(2026, 7, 23, 10);
      final observation = RateObservation(
        currency: CurrencyCode('VES'),
        nativePerUsd: Decimal.parse('37.5'),
        observedAt: observedAt,
        source: 'manual:bcv',
      );

      expect(observation.currency, CurrencyCode('VES'));
      expect(observation.nativePerUsd, Decimal.parse('37.5'));
      expect(observation.observedAt, observedAt);
      expect(observation.source, 'manual:bcv');
    });

    test('source defaults to manual', () {
      final observation = RateObservation(
        currency: CurrencyCode('VES'),
        nativePerUsd: Decimal.parse('37.5'),
        observedAt: DateTime.utc(2026, 7, 23),
      );

      expect(observation.source, 'manual');
    });

    test('equality is value-based', () {
      final observedAt = DateTime.utc(2026, 7, 23);
      final a = RateObservation(
        currency: CurrencyCode('VES'),
        nativePerUsd: Decimal.parse('37.5'),
        observedAt: observedAt,
        source: 'manual:bcv',
      );
      final b = RateObservation(
        currency: CurrencyCode('VES'),
        nativePerUsd: Decimal.parse('37.5'),
        observedAt: observedAt,
        source: 'manual:bcv',
      );

      expect(a, b);
    });
  });
}
