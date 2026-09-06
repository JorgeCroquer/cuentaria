import 'package:contabilidad/domain/transaction.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reportes/reportes.dart';

import '../../../providers/composition_root.dart';
import '../../../providers/tasas_providers.dart';
import 'deudas_en_tiempo_service.dart';

/// The last 12 Debt Points (#265, mirrors [patrimonioEnTiempoPointsProvider]),
/// computed on demand — no persisted snapshot, at most an in-memory cache
/// for this provider's lifetime. Re-subscribes to [eventBusProvider] and
/// invalidates itself on every recorded [Transaction], same convention as
/// `patrimonioSnapshotProvider`.
final debtsEnTiempoPointsProvider = FutureProvider<List<DebtPoint>>((
  ref,
) async {
  final eventBus = ref.watch(eventBusProvider);
  final subscription = eventBus.stream.listen((event) {
    if (event is Transaction) ref.invalidateSelf();
  });
  ref.onDispose(subscription.cancel);
  ref.watch(catalogRevisionProvider);

  final eventStore = await ref.watch(eventStoreProvider.future);
  final catalog = await ref.watch(catalogRepositoryProvider.future);
  final rateSeries = await ref.watch(rateSeriesProvider.future);

  final service = DebtsEnTiempoService(
    eventStore: eventStore,
    catalog: catalog,
    rateSeries: rateSeries,
  );

  final now = DateTime.now();
  final latestMonth = MonthCalendar.getReportMonth(
    now.toUtc(),
    now.timeZoneOffset,
  );

  return service.calculatePoints(latestMonth: latestMonth);
});
