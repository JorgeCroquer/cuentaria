import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reportes/reportes.dart';

import '../../../providers/composition_root.dart';
import '../../../providers/tasas_providers.dart';
import 'envelope_role_mapper.dart';
import 'patrimonio_en_tiempo_service.dart';

const _engine = ExchangeDifferentialEngine();

/// The last 12 months of Diferencial cambiario (#264, ADR-0024 §7), ending
/// at [month] — the same window `PatrimonioEnTiempoService` replays for
/// Patrimonio en el tiempo (#260), so no realizado matches that chart's two
/// lines point for point. Each month's realizado is computed the same way
/// `spendingByEnvelopeProvider` computes its Diferencial realizado row,
/// mapped through the pure [ExchangeDifferentialEngine] instead. Re-
/// subscribes to [eventBusProvider] and invalidates itself on every recorded
/// [Transaction], mirroring `spendingByEnvelopeProvider`'s reactivity
/// pattern.
final exchangeDifferentialProvider = FutureProvider.family<
  List<ExchangeDifferentialPoint>,
  ReportMonth
>((ref, month) async {
  final eventBus = ref.watch(eventBusProvider);
  final subscription = eventBus.stream.listen((event) {
    if (event is Transaction) ref.invalidateSelf();
  });
  ref.onDispose(subscription.cancel);
  ref.watch(catalogRevisionProvider);

  final catalog = await ref.watch(catalogRepositoryProvider.future);
  final store = await ref.watch(eventStoreProvider.future);
  final rateSeries = await ref.watch(rateSeriesProvider.future);
  final allTransactions = await store.queryLog();

  final envelopeViews = [
    for (final envelope in catalog.envelopes)
      EnvelopeView(
        id: envelope.id,
        name: envelope.name,
        role: mapEnvelopeRole(envelope.role),
      ),
  ];

  final patrimonioService = PatrimonioEnTiempoService(
    eventStore: store,
    catalog: catalog,
    rateSeries: rateSeries,
  );
  final points = await patrimonioService.calculatePoints(latestMonth: month);

  final localOffset = DateTime.now().timeZoneOffset;
  return [
    for (final point in points)
      _engine(
        _monthTransactions(point.month, allTransactions, localOffset),
        _monthReversals(point.month, allTransactions, localOffset),
        envelopeViews,
        point,
      ),
  ];
});

List<Transaction> _transactionsInMonth(
  ReportMonth month,
  List<Transaction> allTransactions,
  Duration localOffset,
) =>
    allTransactions
        .where(
          (tx) =>
              MonthCalendar.getReportMonth(
                tx.metadata.occurredAt.value,
                localOffset,
              ) ==
              month,
        )
        .toList();

List<TransactionView> _monthTransactions(
  ReportMonth month,
  List<Transaction> allTransactions,
  Duration localOffset,
) =>
    _transactionsInMonth(
      month,
      allTransactions,
      localOffset,
    ).map(_toView).toList();

List<TransactionView> _monthReversals(
  ReportMonth month,
  List<Transaction> allTransactions,
  Duration localOffset,
) {
  final monthIds =
      _transactionsInMonth(
        month,
        allTransactions,
        localOffset,
      ).map((tx) => tx.metadata.eventId).toSet();
  return allTransactions
      .where(
        (tx) =>
            tx.metadata.reverses != null &&
            monthIds.contains(tx.metadata.reverses),
      )
      .map(_toView)
      .toList();
}

TransactionView _toView(Transaction tx) {
  var hasAccountPosting = false;
  final envelopePostings = <PostingView>[];
  for (final posting in tx.postings) {
    final target = posting.target;
    if (target is AccountTarget) {
      hasAccountPosting = true;
    } else if (target is EnvelopeTarget) {
      envelopePostings.add(
        PostingView(
          envelopeId: target.envelopeId,
          amountUsdCents: posting.amountUsd,
        ),
      );
    }
  }
  return TransactionView(
    id: tx.metadata.eventId,
    reverses: tx.metadata.reverses,
    hasAccountPosting: hasAccountPosting,
    envelopePostings: envelopePostings,
  );
}
