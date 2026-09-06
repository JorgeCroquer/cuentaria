import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:cuentaria_app/providers/tasas_providers.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/domain/rate_observation.dart';

void main() {
  group('recordRateUseCaseProvider', () {
    test(
      'appends BCV and parallel observations, retrievable via rateSeriesProvider',
      () async {
        final container = ProviderContainer(
          overrides: [isWebProvider.overrideWithValue(true)],
        );
        addTearDown(container.dispose);

        final useCase = await container.read(recordRateUseCaseProvider.future);
        final observedAt = DateTime.utc(2026, 7, 23);

        await useCase.execute(
          bcv: RateObservation(
            currency: CurrencyCode('VES'),
            nativePerUsd: Decimal.parse('37.5'),
            observedAt: observedAt,
            source: 'manual:bcv',
          ),
          paralelo: RateObservation(
            currency: CurrencyCode('VES'),
            nativePerUsd: Decimal.parse('90'),
            observedAt: observedAt.add(const Duration(seconds: 1)),
            source: 'manual:paralelo',
          ),
        );

        final series = await container.read(rateSeriesProvider.future);
        final latest = await series.latestFor(CurrencyCode('VES'));
        expect(latest?.source, 'manual:paralelo');
        expect(latest?.nativePerUsd, Decimal.parse('90'));
      },
    );
  });

  group('rate series query providers (#261)', () {
    test(
      'currenciesWithObservationsProvider and rateSeriesObservationsProvider '
      'reflect what was appended to rateSeriesProvider',
      () async {
        final container = ProviderContainer(
          overrides: [isWebProvider.overrideWithValue(true)],
        );
        addTearDown(container.dispose);
        final ves = CurrencyCode('VES');

        final series = await container.read(rateSeriesProvider.future);
        await series.append(
          RateObservation(
            currency: ves,
            nativePerUsd: Decimal.parse('900'),
            observedAt: DateTime.utc(2026, 8, 5),
            source: 'manual:paralelo',
          ),
        );

        final currencies = await container.read(
          currenciesWithObservationsProvider.future,
        );
        expect(currencies, [ves]);

        final observations = await container.read(
          rateSeriesObservationsProvider(ves).future,
        );
        expect(observations, hasLength(1));
        expect(observations.single.source, 'manual:paralelo');

        final candidates = await container.read(
          latestPerSourceProvider(ves).future,
        );
        expect(candidates, hasLength(1));
        expect(candidates.single.source, 'manual:paralelo');
      },
    );
  });
}
