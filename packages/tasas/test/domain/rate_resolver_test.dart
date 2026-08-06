import 'package:decimal/decimal.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/domain/rate_observation.dart';
import 'package:tasas/domain/rate_resolver.dart';
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
  group('resolve', () {
    final ves = CurrencyCode('VES');
    final today = DateTime.utc(2026, 8, 5, 10);

    test('only a manual observation from today: manual wins', () {
      final manual = _obs(
        rate: '845.88',
        observedAt: today,
        source: 'manual:paralelo',
      );

      final resolution = resolve(ves, today, [manual]);

      expect(resolution?.nativePerUsd, Decimal.parse('845.88'));
      expect(resolution?.source, 'manual:paralelo');
      expect(resolution?.observedAt, today);
    });

    test('only a manual observation from June: manual wins, even though '
        'old', () {
      final manual = _obs(
        rate: '690.00',
        observedAt: DateTime.utc(2026, 6, 15),
        source: 'manual:paralelo',
      );

      final resolution = resolve(ves, today, [manual]);

      expect(resolution?.nativePerUsd, Decimal.parse('690.00'));
      expect(resolution?.source, 'manual:paralelo');
    });

    test('manual from June + automatics from today: today\'s automatic '
        'wins because it is a different (more recent) calendar day', () {
      final juneManual = _obs(
        rate: '690.00',
        observedAt: DateTime.utc(2026, 6, 15),
        source: 'manual:paralelo',
      );
      final binance = _obs(
        rate: '845.88',
        observedAt: today,
        source: 'binancep2p:ask',
      );
      final dolarapi = _obs(
        rate: '834.37',
        observedAt: today,
        source: 'dolarapi:paralelo',
      );

      final resolution = resolve(ves, today, [juneManual, binance, dolarapi]);

      expect(resolution?.source, 'binancep2p:ask');
      expect(resolution?.nativePerUsd, Decimal.parse('845.88'));
    });

    test('manual from today + automatics from today: manual wins the '
        'same-day tiebreak', () {
      final manual = _obs(
        rate: '900.00',
        observedAt: today,
        source: 'manual:paralelo',
      );
      final binance = _obs(
        rate: '845.88',
        observedAt: today,
        source: 'binancep2p:ask',
      );
      final dolarapi = _obs(
        rate: '834.37',
        observedAt: today,
        source: 'dolarapi:paralelo',
      );

      final resolution = resolve(ves, today, [manual, binance, dolarapi]);

      expect(resolution?.source, 'manual:paralelo');
      expect(resolution?.nativePerUsd, Decimal.parse('900.00'));
    });

    test('both automatics from today: binancep2p:ask wins — an executable '
        'price, not an aggregator average', () {
      final binance = _obs(
        rate: '845.88',
        observedAt: today,
        source: 'binancep2p:ask',
      );
      final dolarapi = _obs(
        rate: '834.37',
        observedAt: today,
        source: 'dolarapi:paralelo',
      );

      final resolution = resolve(ves, today, [binance, dolarapi]);

      expect(resolution?.source, 'binancep2p:ask');
      expect(resolution?.nativePerUsd, Decimal.parse('845.88'));
    });

    test('only dolarapi:paralelo (Binance down): dolarapi wins', () {
      final dolarapi = _obs(
        rate: '834.37',
        observedAt: today,
        source: 'dolarapi:paralelo',
      );

      final resolution = resolve(ves, today, [dolarapi]);

      expect(resolution?.source, 'dolarapi:paralelo');
      expect(resolution?.nativePerUsd, Decimal.parse('834.37'));
    });

    test('no candidates: null', () {
      expect(resolve(ves, today, []), isNull);
    });

    test('candidates for a different currency are ignored', () {
      final usd = _obs(
        currency: 'USD',
        rate: '1',
        observedAt: today,
        source: 'binancep2p:ask',
      );

      expect(resolve(ves, today, [usd]), isNull);
    });

    test('unrecognized sources (e.g. manual:bcv, dolarapi:oficial) never '
        'win — they are outside the parallel resolution chain', () {
      final bcv = _obs(rate: '45.00', observedAt: today, source: 'manual:bcv');
      final oficial = _obs(
        rate: '48.00',
        observedAt: today,
        source: 'dolarapi:oficial',
      );

      expect(resolve(ves, today, [bcv, oficial]), isNull);
    });

    test('oficialSourcePriority: dolarapi:oficial beats manual:bcv on the '
        'same day', () {
      final bcv = _obs(rate: '45.00', observedAt: today, source: 'manual:bcv');
      final oficial = _obs(
        rate: '48.00',
        observedAt: today,
        source: 'dolarapi:oficial',
      );

      final resolution = resolve(ves, today, [
        bcv,
        oficial,
      ], sourcePriority: oficialSourcePriority);

      expect(resolution?.source, 'dolarapi:oficial');
      expect(resolution?.nativePerUsd, Decimal.parse('48.00'));
    });

    test('oficialSourcePriority: manual:bcv wins as the sole candidate — '
        'the backup the BCV chain falls to when there is no automatic', () {
      final bcv = _obs(rate: '45.00', observedAt: today, source: 'manual:bcv');

      final resolution = resolve(ves, today, [
        bcv,
      ], sourcePriority: oficialSourcePriority);

      expect(resolution?.source, 'manual:bcv');
      expect(resolution?.nativePerUsd, Decimal.parse('45.00'));
    });

    test('oficialSourcePriority: candidates outside it (e.g. '
        'manual:paralelo) never win', () {
      final paralelo = _obs(
        rate: '900.00',
        observedAt: today,
        source: 'manual:paralelo',
      );

      expect(
        resolve(ves, today, [paralelo], sourcePriority: oficialSourcePriority),
        isNull,
      );
    });

    test('asOf in the past resolves with the observations at or before that '
        'date, ignoring later ones', () {
      final past = DateTime.utc(2026, 7, 1);
      final beforeCutoff = _obs(
        rate: '400.00',
        observedAt: DateTime.utc(2026, 6, 30),
        source: 'manual:paralelo',
      );
      final afterCutoff = _obs(
        rate: '420.00',
        observedAt: DateTime.utc(2026, 7, 23),
        source: 'binancep2p:ask',
      );

      final resolution = resolve(ves, past, [beforeCutoff, afterCutoff]);

      expect(resolution?.source, 'manual:paralelo');
      expect(resolution?.nativePerUsd, Decimal.parse('400.00'));
    });

    test('numeric example: binancep2p:ask 845.88 beats dolarapi:paralelo '
        '834.37 observed the same day, freezing 10,000 Bs at \$11.82 (not '
        'the \$11.98 834.37 would give)', () {
      final binance = _obs(
        rate: '845.88',
        observedAt: today,
        source: 'binancep2p:ask',
      );
      final dolarapi = _obs(
        rate: '834.37',
        observedAt: today,
        source: 'dolarapi:paralelo',
      );

      final resolution = resolve(ves, today, [binance, dolarapi]);
      // native = 10,000.00 Bs = 1,000,000 cents; usd = round(native / rate).
      final usdCents =
          (Decimal.fromBigInt(BigInt.from(1000000)) / resolution!.nativePerUsd)
              .round();

      expect(usdCents, BigInt.from(1182));
    });

    test('numeric example: a June manual does not participate once today\'s '
        'automatics exist, so the 10,000 Bs expense still freezes at '
        '\$11.82, not the \$14.49 the June rate of 690.00 would give', () {
      final juneManual = _obs(
        rate: '690.00',
        observedAt: DateTime.utc(2026, 6, 1),
        source: 'manual:paralelo',
      );
      final binance = _obs(
        rate: '845.88',
        observedAt: today,
        source: 'binancep2p:ask',
      );
      final dolarapi = _obs(
        rate: '834.37',
        observedAt: today,
        source: 'dolarapi:paralelo',
      );

      final resolution = resolve(ves, today, [juneManual, binance, dolarapi]);
      final usdCents =
          (Decimal.fromBigInt(BigInt.from(1000000)) / resolution!.nativePerUsd)
              .round();

      expect(resolution.source, 'binancep2p:ask');
      expect(usdCents, BigInt.from(1182));
    });
  });
}
