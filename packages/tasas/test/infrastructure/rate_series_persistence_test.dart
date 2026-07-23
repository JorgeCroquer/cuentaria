/// Proves [DriftRateSeries] observations survive a close/reopen cycle on a
/// file-backed (native) SQLite database — not just `NativeDatabase.memory()`.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:sqlite3/open.dart';
import 'package:tasas/domain/rate_observation.dart';
import 'package:tasas/infrastructure/drift/drift_rate_series.dart';
import 'package:tasas/infrastructure/drift/tasas_database.dart';
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

void main() {
  setUpAll(_ensureSqlite3);

  test('observations appended before a close are readable after reopening the '
      'same database file', () async {
    final dir = Directory.systemTemp.createTempSync('tasas_persistence_test');
    final dbPath = '${dir.path}/tasas.db';

    try {
      var db = TasasDatabase(NativeDatabase(File(dbPath)));
      var series = DriftRateSeries(db);

      final bcv = RateObservation(
        currency: CurrencyCode('VES'),
        nativePerUsd: Decimal.parse('37.5'),
        observedAt: DateTime.utc(2026, 7, 23, 9),
        source: 'manual:bcv',
      );
      final paralelo = RateObservation(
        currency: CurrencyCode('VES'),
        nativePerUsd: Decimal.parse('90'),
        observedAt: DateTime.utc(2026, 7, 23, 9, 1),
        source: 'manual:paralelo',
      );

      await series.append(bcv);
      await series.append(paralelo);
      await db.close();

      db = TasasDatabase(NativeDatabase(File(dbPath)));
      series = DriftRateSeries(db);

      final latest = await series.latestFor(CurrencyCode('VES'));
      expect(latest, paralelo);

      await db.close();
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
