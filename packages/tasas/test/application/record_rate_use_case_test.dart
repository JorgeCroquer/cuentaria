import 'package:decimal/decimal.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/application/record_rate_use_case.dart';
import 'package:tasas/domain/rate_observation.dart';
import 'package:tasas/domain/rate_series.dart';
import 'package:test/test.dart';

class _RecordingRateSeries implements RateSeries {
  final List<RateObservation> appended = [];

  @override
  Future<void> append(RateObservation observation) async {
    appended.add(observation);
  }

  @override
  Future<RateObservation?> latestFor(
    CurrencyCode currency, {
    String? source,
    DateTime? asOf,
  }) async => throw UnimplementedError();

  @override
  Future<List<RateObservation>> candidatesFor(
    CurrencyCode currency, {
    DateTime? asOf,
  }) async => throw UnimplementedError();
}

RateObservation _obs({
  String currency = 'VES',
  String rate = '37.5',
  DateTime? observedAt,
  required String source,
}) => RateObservation(
  currency: CurrencyCode(currency),
  nativePerUsd: Decimal.parse(rate),
  observedAt: observedAt ?? DateTime.utc(2026, 7, 23),
  source: source,
);

void main() {
  group('RecordRateUseCase', () {
    test('appends both the BCV and parallel observations', () async {
      final series = _RecordingRateSeries();
      final useCase = RecordRateUseCase(series);

      final bcv = _obs(rate: '37.5', source: 'manual:bcv');
      final paralelo = _obs(rate: '90', source: 'manual:paralelo');

      await useCase.execute(bcv: bcv, paralelo: paralelo);

      expect(series.appended, [bcv, paralelo]);
    });

    test('rejects mismatched currencies', () async {
      final series = _RecordingRateSeries();
      final useCase = RecordRateUseCase(series);

      final bcv = _obs(currency: 'VES', source: 'manual:bcv');
      final paralelo = _obs(currency: 'USD', source: 'manual:paralelo');

      expect(
        () => useCase.execute(bcv: bcv, paralelo: paralelo),
        throwsArgumentError,
      );
      expect(series.appended, isEmpty);
    });
  });
}
