import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/application/rate_resolution_service.dart';
import 'package:tasas/application/record_rate_use_case.dart';
import 'package:tasas/application/sync_rate_series_use_case.dart';
import 'package:tasas/domain/rate_feed.dart';
import 'package:tasas/domain/rate_resolver.dart';
import 'package:tasas/domain/rate_series.dart';
import 'package:tasas/infrastructure/drift/drift_rate_series.dart';
import 'package:tasas/infrastructure/drift/tasas_database.dart';
import 'package:tasas/infrastructure/http/http_rate_feed.dart';
import 'package:tasas/infrastructure/in_memory/in_memory_rate_feed.dart';
import 'package:tasas/infrastructure/in_memory/in_memory_rate_series.dart';

import '../infrastructure/persistence/open_tasas_database_stub.dart'
    if (dart.library.io) '../infrastructure/persistence/open_tasas_database_native.dart';
import 'composition_root.dart';

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

/// The published rate feed (S2, ADR-0020 §1). Web has no CORS-friendly
/// path to a raw GitHub Release asset and no durable storage to sync into
/// either — see [isWebProvider] — so it gets an empty in-memory feed
/// instead of a real network call.
final rateFeedProvider = Provider<RateFeed>((ref) {
  if (ref.watch(isWebProvider)) {
    return InMemoryRateFeed('');
  }
  return HttpRateFeed();
});

final syncRateSeriesUseCaseProvider = FutureProvider<SyncRateSeriesUseCase>((
  ref,
) async {
  final feed = ref.watch(rateFeedProvider);
  final series = await ref.watch(rateSeriesProvider.future);
  return SyncRateSeriesUseCase(feed, series);
});

/// Latest resolved parallel Rate (#165, ADR-0020 §4), watched reactively so
/// the capture sheet can gate Save and show a valuation hint without any
/// polling — invalidated by [RecordRatesDialog] whenever a new rate is
/// registered.
final latestParaleloRateProvider =
    FutureProvider.family<Resolution?, CurrencyCode>((ref, currency) async {
      final series = await ref.watch(rateSeriesProvider.future);
      return RateResolutionService(series)(currency);
    });

/// Latest resolved BCV/"oficial" Rate (#166, #175), the same Chain as
/// [latestParaleloRateProvider] but resolved with [oficialSourcePriority] —
/// used to pre-fill the manual rates form so accepting the suggestion never
/// fabricates a `manual:bcv` observation that would outrank the real
/// `dolarapi:oficial` reading (ADR-0020).
final latestOficialRateProvider =
    FutureProvider.family<Resolution?, CurrencyCode>((ref, currency) async {
      final series = await ref.watch(rateSeriesProvider.future);
      return RateResolutionService(series)(
        currency,
        sourcePriority: oficialSourcePriority,
      );
    });

/// Resolved parallel Rate for [currency] as of a given date (ADR-0019 §5)
/// — used by routed Reconciliation capture to preview what a
/// late-registered Income/Expense will freeze at.
final paraleloRateAsOfProvider =
    FutureProvider.family<Resolution?, (CurrencyCode, DateTime)>((
      ref,
      key,
    ) async {
      final (currency, asOf) = key;
      final series = await ref.watch(rateSeriesProvider.future);
      return RateResolutionService(series)(currency, asOf: asOf);
    });
