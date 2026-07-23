import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasas/application/record_rate_use_case.dart';
import 'package:tasas/domain/rate_series.dart';
import 'package:tasas/infrastructure/drift/drift_rate_series.dart';
import 'package:tasas/infrastructure/drift/tasas_database.dart';
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
