import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/application/record_rate_use_case.dart';
import 'package:tasas/domain/rate_observation.dart';
import 'package:tasas/domain/rate_series.dart';
import 'package:tasas/infrastructure/drift/drift_rate_series.dart';
import 'package:tasas/infrastructure/drift/tasas_database.dart';
import 'package:tasas/infrastructure/in_memory/in_memory_rate_series.dart';

import '../infrastructure/persistence/open_tasas_database_stub.dart'
    if (dart.library.io) '../infrastructure/persistence/open_tasas_database_native.dart';
import 'composition_root.dart';

const _paraleloSource = 'manual:paralelo';

/// Opens the tasas rates database. Only resolved on native platforms — see
/// [isWebProvider].
final tasasDatabaseProvider = FutureProvider<TasasDatabase>((ref) async {
  return TasasDatabase(await openTasasDatabase());
});

final rateSeriesProvider = FutureProvider<RateSeries>((ref) async {
  if (ref.watch(isWebProvider)) {
    return InMemoryRateSeries();
  }
  final db = await ref.watch(tasasDatabaseProvider.future);
  return DriftRateSeries(db);
});

final recordRateUseCaseProvider = FutureProvider<RecordRateUseCase>((
  ref,
) async {
  final series = await ref.watch(rateSeriesProvider.future);
  return RecordRateUseCase(series);
});

/// Latest parallel Rate Observation for [currency] (ADR-0018), watched
/// reactively so the capture sheet can gate Save and show a valuation
/// hint without any polling — invalidated by [RecordRatesDialog] whenever
/// a new rate is registered.
final latestParaleloRateProvider =
    FutureProvider.family<RateObservation?, CurrencyCode>((
      ref,
      currency,
    ) async {
      final series = await ref.watch(rateSeriesProvider.future);
      return series.latestFor(currency, source: _paraleloSource);
    });

/// Parallel Rate Observation for [currency] as of a given date, or the
/// nearest one before it (ADR-0019 §5) — used by routed Reconciliation
/// capture to preview what a late-registered Income/Expense will freeze at.
final paraleloRateAsOfProvider =
    FutureProvider.family<RateObservation?, (CurrencyCode, DateTime)>((
      ref,
      key,
    ) async {
      final (currency, asOf) = key;
      final series = await ref.watch(rateSeriesProvider.future);
      return series.latestFor(currency, source: _paraleloSource, asOf: asOf);
    });
