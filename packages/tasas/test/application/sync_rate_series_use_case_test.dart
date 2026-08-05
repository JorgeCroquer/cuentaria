/// Idempotence contract for [SyncRateSeriesUseCase], run against the SAME
/// two [RateSeries] adapters as [rate_series_contract_test.dart] plus a
/// dedicated Drift row-count check, so idempotence is proven against the
/// real persistence layer, not just the in-memory reference.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:sqlite3/open.dart';
import 'package:tasas/application/sync_rate_series_use_case.dart';
import 'package:tasas/domain/rate_series.dart';
import 'package:tasas/infrastructure/drift/drift_rate_series.dart';
import 'package:tasas/infrastructure/drift/tasas_database.dart';
import 'package:tasas/infrastructure/in_memory/in_memory_rate_feed.dart';
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

const _ndjson =
    '{"currency":"VES","source":"dolarapi:paralelo","nativePerUsd":"834.370612","observedAt":"2026-08-05T10:00:00.000Z"}\n'
    '{"currency":"VES","source":"binancep2p:ask","nativePerUsd":"845.88","observedAt":"2026-08-05T10:00:00.000Z"}';

typedef _Factory = Future<RateSeries> Function();
typedef _Teardown = Future<void> Function();

void _runIdempotenceSuite(
  String label,
  _Factory makeSeries, {
  _Teardown? teardown,
}) {
  group('SyncRateSeriesUseCase idempotence [$label]', () {
    late RateSeries series;

    setUp(() async {
      series = await makeSeries();
    });

    tearDown(() async {
      await teardown?.call();
    });

    test('syncing the same feed twice leaves each observation as-is', () async {
      final useCase = SyncRateSeriesUseCase(InMemoryRateFeed(_ndjson), series);

      await useCase.sync();
      await useCase.sync();

      final paralelo = await series.latestFor(
        CurrencyCode('VES'),
        source: 'dolarapi:paralelo',
      );
      expect(paralelo?.nativePerUsd, Decimal.parse('834.370612'));

      final ask = await series.latestFor(
        CurrencyCode('VES'),
        source: 'binancep2p:ask',
      );
      expect(ask?.nativePerUsd, Decimal.parse('845.88'));
    });
  });
}

void main() {
  setUpAll(_ensureSqlite3);

  test('sync appends every observation the feed reports', () async {
    final series = InMemoryRateSeries();
    final useCase = SyncRateSeriesUseCase(InMemoryRateFeed(_ndjson), series);

    await useCase.sync();

    expect(
      await series.latestFor(CurrencyCode('VES'), source: 'dolarapi:paralelo'),
      isNotNull,
    );
    expect(
      await series.latestFor(CurrencyCode('VES'), source: 'binancep2p:ask'),
      isNotNull,
    );
  });

  test('an empty feed (fetch failed or nothing new) appends nothing', () async {
    final series = InMemoryRateSeries();
    final useCase = SyncRateSeriesUseCase(InMemoryRateFeed(''), series);

    await useCase.sync();

    expect(await series.latestFor(CurrencyCode('VES')), isNull);
  });

  _runIdempotenceSuite('InMemoryRateSeries', () async => InMemoryRateSeries());

  late TasasDatabase db;
  _runIdempotenceSuite('DriftRateSeries', () async {
    db = TasasDatabase(NativeDatabase.memory());
    return DriftRateSeries(db);
  }, teardown: () async => db.close());

  test(
    'syncing the same feed twice against Drift never inserts a duplicate row',
    () async {
      final db = TasasDatabase(NativeDatabase.memory());
      final series = DriftRateSeries(db);
      final useCase = SyncRateSeriesUseCase(InMemoryRateFeed(_ndjson), series);

      await useCase.sync();
      await useCase.sync();

      final rows = await db.select(db.rateObservations).get();
      expect(rows, hasLength(2));

      await db.close();
    },
  );
}
