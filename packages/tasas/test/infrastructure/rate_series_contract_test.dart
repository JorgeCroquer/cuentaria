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

    test('latestFor returns null for a currency with no observations', () async {
      expect(await series.latestFor(CurrencyCode('USD')), isNull);
    });

    test('latestFor returns the most recent observation per currency', () async {
      final older = _obs(observedAt: DateTime.utc(2026, 7, 20), rate: '36');
      final newer = _obs(observedAt: DateTime.utc(2026, 7, 23), rate: '38');
      await series.append(older);
      await series.append(newer);

      expect(await series.latestFor(CurrencyCode('VES')), newer);
    });

    test('appends out of chronological order still resolve to the max', () async {
      final oldest = _obs(observedAt: DateTime.utc(2026, 7, 1), rate: '35');
      final newest = _obs(observedAt: DateTime.utc(2026, 7, 23), rate: '38');
      final middle = _obs(observedAt: DateTime.utc(2026, 7, 10), rate: '36');

      await series.append(newest);
      await series.append(oldest);
      await series.append(middle);

      expect(await series.latestFor(CurrencyCode('VES')), newest);
    });

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

    test(
      'two observations at the same instant are both stored; '
      'latestFor resolves to the last one appended',
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

        expect(await series.latestFor(CurrencyCode('VES')), paralelo);
      },
    );
  });
}

void main() {
  setUpAll(_ensureSqlite3);

  _runContractSuite('InMemoryRateSeries', () async => InMemoryRateSeries());

  late TasasDatabase db;
  _runContractSuite(
    'DriftRateSeries',
    () async {
      db = TasasDatabase(NativeDatabase.memory());
      return DriftRateSeries(db);
    },
    teardown: () async => db.close(),
  );
}
