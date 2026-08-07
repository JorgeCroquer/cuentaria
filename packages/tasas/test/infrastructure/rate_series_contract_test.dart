/// Parametrized contract/parity suite for [RateSeries].
///
/// Runs the SAME behavioral contract against:
///   - [InMemoryRateSeries]  (reference implementation)
///   - [DriftRateSeries]     (Drift/SQLite adapter, unencrypted per ADR-0016)
library;

import 'dart:ffi';
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:sqlite3/open.dart';
import 'package:tasas/domain/rate_observation.dart';
import 'package:tasas/domain/rate_series.dart';
import 'package:tasas/infrastructure/drift/drift_rate_series.dart';
import 'package:tasas/infrastructure/drift/tasas_database.dart';
import 'package:tasas/infrastructure/in_memory/in_memory_rate_series.dart';
import 'package:test/test.dart';

void _ensureSqlite3() {
  if (!Platform.isLinux) return;
  open.overrideForAll(() {
    try {
      return DynamicLibrary.open('libsqlite3.so');
    } catch (_) {
      // ignore: empty_catches
    }
    return DynamicLibrary.open('libsqlite3.so.0');
  });
}

RateObservation _obs({
  String currency = 'VES',
  String rate = '37.5',
  required DateTime observedAt,
  String source = 'manual',
}) => RateObservation(
  currency: CurrencyCode(currency),
  nativePerUsd: Decimal.parse(rate),
  observedAt: observedAt,
  source: source,
);

typedef _Factory = Future<RateSeries> Function();
typedef _Teardown = Future<void> Function();

void _runContractSuite(
  String label,
  _Factory makeSeries, {
  _Teardown? teardown,
}) {
  group('RateSeries contract [$label]', () {
    late RateSeries series;

    setUp(() async {
      series = await makeSeries();
    });

    tearDown(() async {
      await teardown?.call();
    });

    test('append then latestFor returns the observation', () async {
      final obs = _obs(observedAt: DateTime.utc(2026, 7, 23));
      await series.append(obs);
      expect(await series.latestFor(CurrencyCode('VES')), obs);
    });

    test(
      'latestFor returns null for a currency with no observations',
      () async {
        expect(await series.latestFor(CurrencyCode('USD')), isNull);
      },
    );

    test(
      'latestFor returns the most recent observation per currency',
      () async {
        final older = _obs(observedAt: DateTime.utc(2026, 7, 20), rate: '36');
        final newer = _obs(observedAt: DateTime.utc(2026, 7, 23), rate: '38');
        await series.append(older);
        await series.append(newer);

        expect(await series.latestFor(CurrencyCode('VES')), newer);
      },
    );

    test(
      'appends out of chronological order still resolve to the max',
      () async {
        final oldest = _obs(observedAt: DateTime.utc(2026, 7, 1), rate: '35');
        final newest = _obs(observedAt: DateTime.utc(2026, 7, 23), rate: '38');
        final middle = _obs(observedAt: DateTime.utc(2026, 7, 10), rate: '36');

        await series.append(newest);
        await series.append(oldest);
        await series.append(middle);

        expect(await series.latestFor(CurrencyCode('VES')), newest);
      },
    );

    test('latestFor is scoped to the requested currency', () async {
      final ves = _obs(currency: 'VES', observedAt: DateTime.utc(2026, 7, 23));
      final usd = _obs(
        currency: 'USD',
        rate: '1',
        observedAt: DateTime.utc(2026, 7, 22),
      );
      await series.append(ves);
      await series.append(usd);

      expect(await series.latestFor(CurrencyCode('USD')), usd);
      expect(await series.latestFor(CurrencyCode('VES')), ves);
    });

    test('two observations at the same instant are both stored; '
        'latestFor resolves to the last one appended', () async {
      final sameInstant = DateTime.utc(2026, 7, 23, 12);
      final bcv = _obs(
        observedAt: sameInstant,
        rate: '37',
        source: 'manual:bcv',
      );
      final paralelo = _obs(
        observedAt: sameInstant,
        rate: '90',
        source: 'manual:paralelo',
      );

      await series.append(bcv);
      await series.append(paralelo);

      expect(await series.latestFor(CurrencyCode('VES')), paralelo);
    });

    test(
      'latestFor(source: ...) scopes to that source, so BCV stays reachable '
      'even after a later parallel observation at the same instant',
      () async {
        final sameInstant = DateTime.utc(2026, 7, 23, 12);
        final bcv = _obs(
          observedAt: sameInstant,
          rate: '37',
          source: 'manual:bcv',
        );
        final paralelo = _obs(
          observedAt: sameInstant,
          rate: '90',
          source: 'manual:paralelo',
        );

        await series.append(bcv);
        await series.append(paralelo);

        expect(
          await series.latestFor(CurrencyCode('VES'), source: 'manual:bcv'),
          bcv,
        );
        expect(
          await series.latestFor(
            CurrencyCode('VES'),
            source: 'manual:paralelo',
          ),
          paralelo,
        );
      },
    );

    test('latestFor(source: ...) returns null when that source has no '
        'observation for the currency', () async {
      await series.append(
        _obs(observedAt: DateTime.utc(2026, 7, 23), source: 'manual:bcv'),
      );

      expect(
        await series.latestFor(CurrencyCode('VES'), source: 'manual:paralelo'),
        isNull,
      );
    });

    test('latestFor(asOf: ...) returns the observation recorded exactly on '
        'that date when it is the most recent one at or before it', () async {
      final target = _obs(observedAt: DateTime.utc(2026, 7, 20), rate: '400');
      await series.append(target);

      expect(
        await series.latestFor(
          CurrencyCode('VES'),
          asOf: DateTime.utc(2026, 7, 20),
        ),
        target,
      );
    });

    test('latestFor(asOf: ...) returns the most recent observation at or '
        'before that date, ignoring later ones', () async {
      final before = _obs(observedAt: DateTime.utc(2026, 7, 1), rate: '380');
      final onTarget = _obs(observedAt: DateTime.utc(2026, 7, 10), rate: '390');
      final after = _obs(observedAt: DateTime.utc(2026, 7, 23), rate: '420');
      await series.append(before);
      await series.append(onTarget);
      await series.append(after);

      expect(
        await series.latestFor(
          CurrencyCode('VES'),
          asOf: DateTime.utc(2026, 7, 20),
        ),
        onTarget,
      );
    });

    test('latestFor(asOf: ...) returns null when every observation is '
        'after that date', () async {
      await series.append(_obs(observedAt: DateTime.utc(2026, 7, 23)));

      expect(
        await series.latestFor(
          CurrencyCode('VES'),
          asOf: DateTime.utc(2026, 7, 1),
        ),
        isNull,
      );
    });

    test('two observations on the same day both qualify for asOf; the last '
        'one appended wins the tiebreak', () async {
      final sameDay = DateTime.utc(2026, 7, 20);
      final first = _obs(observedAt: sameDay, rate: '400');
      final second = _obs(observedAt: sameDay, rate: '405');
      await series.append(first);
      await series.append(second);

      expect(
        await series.latestFor(CurrencyCode('VES'), asOf: sameDay),
        second,
      );
    });

    test('latestFor(asOf: ..., source: ...) combines both scopes', () async {
      final sameInstant = DateTime.utc(2026, 7, 20, 12);
      final bcv = _obs(
        observedAt: sameInstant,
        rate: '390',
        source: 'manual:bcv',
      );
      final paralelo = _obs(
        observedAt: sameInstant,
        rate: '400',
        source: 'manual:paralelo',
      );
      final laterParalelo = _obs(
        observedAt: DateTime.utc(2026, 7, 23),
        rate: '420',
        source: 'manual:paralelo',
      );
      await series.append(bcv);
      await series.append(paralelo);
      await series.append(laterParalelo);

      expect(
        await series.latestFor(
          CurrencyCode('VES'),
          source: 'manual:paralelo',
          asOf: sameInstant,
        ),
        paralelo,
      );
    });

    test('candidatesFor returns an empty list for a currency with no '
        'observations', () async {
      expect(await series.candidatesFor(CurrencyCode('VES')), isEmpty);
    });

    test(
      'candidatesFor returns the latest observation of each source',
      () async {
        final olderManual = _obs(
          observedAt: DateTime.utc(2026, 8, 1),
          rate: '800',
          source: 'manual:paralelo',
        );
        final newerManual = _obs(
          observedAt: DateTime.utc(2026, 8, 5),
          rate: '900',
          source: 'manual:paralelo',
        );
        final binance = _obs(
          observedAt: DateTime.utc(2026, 8, 5),
          rate: '845.88',
          source: 'binancep2p:ask',
        );
        final bcv = _obs(
          observedAt: DateTime.utc(2026, 8, 5),
          rate: '45',
          source: 'manual:bcv',
        );
        await series.append(olderManual);
        await series.append(newerManual);
        await series.append(binance);
        await series.append(bcv);

        final candidates = await series.candidatesFor(CurrencyCode('VES'));

        expect(candidates, containsAll([newerManual, binance, bcv]));
        expect(candidates, isNot(contains(olderManual)));
        expect(candidates.length, 3);
      },
    );

    test('candidatesFor is scoped to the requested currency', () async {
      final ves = _obs(currency: 'VES', observedAt: DateTime.utc(2026, 8, 5));
      final usd = _obs(
        currency: 'USD',
        rate: '1',
        observedAt: DateTime.utc(2026, 8, 5),
      );
      await series.append(ves);
      await series.append(usd);

      expect(await series.candidatesFor(CurrencyCode('VES')), [ves]);
    });

    test(
      'candidatesFor(asOf: ...) ignores observations after that date',
      () async {
        final before = _obs(
          observedAt: DateTime.utc(2026, 7, 1),
          rate: '400',
          source: 'manual:paralelo',
        );
        final after = _obs(
          observedAt: DateTime.utc(2026, 8, 5),
          rate: '420',
          source: 'manual:paralelo',
        );
        await series.append(before);
        await series.append(after);

        expect(
          await series.candidatesFor(
            CurrencyCode('VES'),
            asOf: DateTime.utc(2026, 7, 20),
          ),
          [before],
        );
      },
    );

    test('allObservations returns an empty list for a fresh series', () async {
      expect(await series.allObservations(), isEmpty);
    });

    test('allObservations returns every observation across currencies and '
        'sources, ordered by observedAt', () async {
      final ves = _obs(
        currency: 'VES',
        observedAt: DateTime.utc(2026, 7, 23),
        source: 'manual:paralelo',
      );
      final usd = _obs(
        currency: 'USD',
        rate: '1',
        observedAt: DateTime.utc(2026, 7, 1),
      );
      final bcv = _obs(
        currency: 'VES',
        observedAt: DateTime.utc(2026, 7, 10),
        source: 'manual:bcv',
      );

      await series.append(ves);
      await series.append(usd);
      await series.append(bcv);

      expect(await series.allObservations(), equals([usd, bcv, ves]));
    });
  });
}

void main() {
  setUpAll(_ensureSqlite3);

  _runContractSuite('InMemoryRateSeries', () async => InMemoryRateSeries());

  late TasasDatabase db;
  _runContractSuite('DriftRateSeries', () async {
    db = TasasDatabase(NativeDatabase.memory());
    return DriftRateSeries(db);
  }, teardown: () async => db.close());
}
