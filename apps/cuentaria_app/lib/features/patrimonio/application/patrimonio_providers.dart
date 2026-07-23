import 'package:contabilidad/domain/transaction.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/composition_root.dart';

/// Net worth at real cost, in USD cents: the sum of every non-archived
/// Account's real-cost balance from the ledger projections (ADR-0006 — no
/// market overlay yet). Re-subscribes to [eventBusProvider] and invalidates
/// itself on every recorded [Transaction], so the header never goes stale
/// after the first paint.
final netWorthUsdProvider = FutureProvider<int>((ref) async {
  final eventBus = ref.watch(eventBusProvider);
  final subscription = eventBus.stream.listen((event) {
    if (event is Transaction) ref.invalidateSelf();
  });
  ref.onDispose(subscription.cancel);

  final catalog = await ref.watch(catalogRepositoryProvider.future);
  final projections = ref.watch(ledgerProjectionsProvider);

  var totalUsd = 0;
  for (final account in catalog.accounts) {
    if (account.isArchived) continue;
    totalUsd += projections.accountBalance(account.id).usd;
  }
  return totalUsd;
});
