import 'package:decimal/decimal.dart';
import 'package:rates/run_rates.dart';
import 'package:rates/sources/rate_source.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/domain/rate_observation.dart';
import 'package:tasas/infrastructure/ndjson/ndjson_rate_store.dart';
import 'package:test/test.dart';

class _FakeSource implements RateSource {
  final List<RateObservation> Function() _onFetch;

  _FakeSource(this._onFetch);

  @override
  Future<List<RateObservation>> fetch() async => _onFetch();
}

RateObservation _obs(String source, DateTime observedAt) => RateObservation(
  currency: CurrencyCode('VES'),
  source: source,
  nativePerUsd: Decimal.parse('834.370612'),
  observedAt: observedAt,
);

void main() {
  group('runRates', () {
    test(
      'merges observations from every source into the existing feed',
      () async {
        final a = _obs('dolarapi:oficial', DateTime.utc(2026, 8, 5, 4));
        final b = _obs('binancep2p:ask', DateTime.utc(2026, 8, 5, 4));

        final result = await runRates(
          existingNdjson: '',
          sources: [
            _FakeSource(() => [a]),
            _FakeSource(() => [b]),
          ],
        );

        final store = NdjsonRateStore.parse(result!);
        expect(store.observations, containsAll([a, b]));
      },
    );

    test(
      'one source failing still publishes the other source\'s observations',
      () async {
        final a = _obs('dolarapi:oficial', DateTime.utc(2026, 8, 5, 4));

        final result = await runRates(
          existingNdjson: '',
          sources: [
            _FakeSource(() => throw Exception('source down')),
            _FakeSource(() => [a]),
          ],
        );

        final store = NdjsonRateStore.parse(result!);
        expect(store.observations, [a]);
      },
    );

    test('both sources failing publishes nothing', () async {
      final result = await runRates(
        existingNdjson: '',
        sources: [
          _FakeSource(() => throw Exception('source down')),
          _FakeSource(() => throw Exception('source down')),
        ],
      );

      expect(result, isNull);
    });

    test(
      'no new observations over an already-populated feed publishes nothing',
      () async {
        final a = _obs('dolarapi:oficial', DateTime.utc(2026, 8, 5, 4));
        final existing = NdjsonRateStore.parse('');
        existing.append(a);

        final result = await runRates(
          existingNdjson: existing.serialize(),
          sources: [
            _FakeSource(() => [a]),
          ],
        );

        expect(result, isNull);
      },
    );
  });
}
