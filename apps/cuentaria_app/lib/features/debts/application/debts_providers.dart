import 'package:contabilidad/domain/transaction.dart';
import 'package:deudas/deudas.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/application/rate_resolution_service.dart';

import '../../../providers/composition_root.dart';
import '../../../providers/tasas_providers.dart';

const _engine = DebtsEngine();

/// The Deudas snapshot (#207, ADR-0022), computed by the pure [DebtsEngine].
/// Mirrors patrimonioSnapshotProvider's composition-root mapping: contabilidad's
/// catalog/ledger and tasas' rate series into deudas' own
/// [DebtAccountView]/[RateView] — deudas never imports another context's
/// `domain/` (ADR-0005), so that mapping lives here.
final debtsSnapshotProvider = FutureProvider<DebtsSnapshot>((ref) async {
  final eventBus = ref.watch(eventBusProvider);
  final subscription = eventBus.stream.listen((event) {
    if (event is Transaction) ref.invalidateSelf();
  });
  ref.onDispose(subscription.cancel);

  final catalog = await ref.watch(catalogRepositoryProvider.future);
  final projections = ref.watch(ledgerProjectionsProvider);
  final series = await ref.watch(rateSeriesProvider.future);

  final accounts = [
    for (final account in catalog.accounts)
      if (account.isDebtAccount)
        DebtAccountView(
          id: account.id,
          counterpartyName: account.counterpartyName!,
          currency: account.nativeCurrency,
          nativeMinorAmount:
              projections.accountBalance(account.id).native.amount,
          realCostUsdCents: projections.accountBalance(account.id).usd,
          isArchived: account.isArchived,
        ),
  ];

  final usd = CurrencyCode('USD');
  final foreignCurrencies =
      accounts.map((a) => a.currency).where((c) => c != usd).toSet();

  final rates = <CurrencyCode, RateView>{};
  for (final currency in foreignCurrencies) {
    final parallel = await RateResolutionService(series)(currency);
    if (parallel == null) continue;

    rates[currency] = RateView(
      currency: currency,
      parallel: RateObservationView(
        nativePerUsd: parallel.nativePerUsd,
        observedAt: parallel.observedAt,
        source: parallel.source,
      ),
    );
  }

  return _engine(accounts, rates, DateTime.now().toUtc());
});
