import 'package:decimal/decimal.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/domain/rate_observation.dart';
import 'package:tasas/infrastructure/ndjson/ndjson_rate_store.dart';
import 'package:test/test.dart';

RateObservation _obs({
  String currency = 'VES',
  String source = 'dolarapi:oficial',
  String rate = '755.1552',
  required DateTime observedAt,
}) => RateObservation(
  currency: CurrencyCode(currency),
  source: source,
  nativePerUsd: Decimal.parse(rate),
  observedAt: observedAt,
);

void main() {
  group('NdjsonRateStore', () {
    test('parses an empty feed', () {
      final store = NdjsonRateStore.parse('');
      expect(store.observations, isEmpty);
    });

    test('appending a new observation returns true and is serialized back', () {
      final store = NdjsonRateStore.parse('');
      final obs = _obs(observedAt: DateTime.utc(2026, 8, 5, 4));

      expect(store.append(obs), isTrue);

      final reparsed = NdjsonRateStore.parse(store.serialize());
      expect(reparsed.observations, [obs]);
    });

    test(
      'appending the same (currency, source, observedAt) twice is a no-op',
      () {
        final store = NdjsonRateStore.parse('');
        final obs = _obs(observedAt: DateTime.utc(2026, 8, 5, 4));

        expect(store.append(obs), isTrue);
        expect(store.append(obs), isFalse);
        expect(store.observations, hasLength(1));
      },
    );

    test(
      'previously published lines are preserved verbatim and new ones are appended after them',
      () {
        final existing = _obs(
          source: 'dolarapi:oficial',
          rate: '750',
          observedAt: DateTime.utc(2026, 8, 5, 4),
        );
        final store = NdjsonRateStore.parse(_serializeOne(existing));

        final fresh = _obs(
          source: 'dolarapi:paralelo',
          rate: '834.370612',
          observedAt: DateTime.utc(2026, 8, 5, 10),
        );
        store.append(fresh);

        expect(store.observations, [existing, fresh]);
      },
    );

    test('re-parsing dedups a feed that already contains the observation', () {
      final obs = _obs(observedAt: DateTime.utc(2026, 8, 5, 4));
      final store = NdjsonRateStore.parse(_serializeOne(obs));

      expect(store.append(obs), isFalse);
      expect(store.observations, hasLength(1));
    });
  });
}

String _serializeOne(RateObservation obs) {
  final store = NdjsonRateStore.parse('');
  store.append(obs);
  return store.serialize();
}
