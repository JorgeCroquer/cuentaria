import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/catalog/models/funding_target.dart'
    as contabilidad;
import 'package:contabilidad/domain/transaction.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:patrimonio/patrimonio.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/application/rate_resolution_service.dart';
import 'package:tasas/domain/rate_resolver.dart';

import '../../../providers/composition_root.dart';
import '../../../providers/tasas_providers.dart';
import '../../debts/application/debts_providers.dart';

const _engine = PatrimonioEngine();

/// The Patrimonio header + accounts block (ADR-0016), computed by the pure
/// [PatrimonioEngine]. This is the composition root's mapping from
/// contabilidad's catalog/ledger and tasas' rate series into patrimonio's
/// own [AccountView]/[RateView] — patrimonio never imports another
/// context's `domain/` (ADR-0005), so that mapping lives here, not in the
/// widget tree or in the patrimonio package itself.
///
/// Re-subscribes to [eventBusProvider] and invalidates itself on every
/// recorded [Transaction]; manual rate capture invalidates it explicitly
/// (tasas has no domain events to subscribe to).
final patrimonioSnapshotProvider = FutureProvider<PatrimonioSnapshot>((
  ref,
) async {
  final eventBus = ref.watch(eventBusProvider);
  final subscription = eventBus.stream.listen((event) {
    if (event is Transaction) ref.invalidateSelf();
  });
  ref.onDispose(subscription.cancel);
  ref.watch(catalogRevisionProvider);

  final catalog = await ref.watch(catalogRepositoryProvider.future);
  final projections = ref.watch(ledgerProjectionsProvider);
  final series = await ref.watch(rateSeriesProvider.future);

  final accounts = [
    for (final account in catalog.accounts)
      if (!account.isDebtAccount)
        AccountView(
          id: account.id,
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
    final bcv = await RateResolutionService(series)(
      currency,
      sourcePriority: oficialSourcePriority,
    );
    if (parallel == null && bcv == null) continue;

    rates[currency] = RateView(
      currency: currency,
      parallel:
          parallel == null
              ? null
              : RateObservationView(
                nativePerUsd: parallel.nativePerUsd,
                observedAt: parallel.observedAt,
                source: parallel.source,
              ),
      bcv:
          bcv == null
              ? null
              : RateObservationView(
                nativePerUsd: bcv.nativePerUsd,
                observedAt: bcv.observedAt,
                source: bcv.source,
              ),
    );
  }

  final envelopes = [
    for (final envelope in catalog.envelopes)
      if (!envelope.isArchived)
        EnvelopeView(
          id: envelope.id,
          name: envelope.name,
          role: _mapRole(envelope.role),
          balanceUsd: projections.envelopeUsdBalance(envelope.id),
          target: _mapTarget(envelope.target),
          iconId: envelope.appearance.iconId,
          colorIndex: envelope.appearance.colorIndex,
        ),
  ];

  final snapshot = _engine(accounts, rates, envelopes, DateTime.now().toUtc());

  // Debt Accounts are excluded from `accounts` above (#207) so they never
  // land in a currency group — the Deudas screen owns their presentation.
  // Their value is added back into the totals here so segregating moves
  // presentation, not numbers: net worth stays identical to when they were
  // still mixed into their currency's group.
  final debts = await ref.watch(debtsSnapshotProvider.future);
  final debtsRealCostUsdCents = [
    for (final persona in debts.personas)
      for (final leg in persona.currencies) leg.realCostUsdCents,
  ].fold(0, (sum, cost) => sum + cost);
  final realCostUsdCents = snapshot.realCostUsdCents + debtsRealCostUsdCents;
  final todayValueUsdCents =
      snapshot.todayValueUsdCents + debts.globalNetoUsdCents;
  final bcvReferenceUsdCents =
      snapshot.bcvReferenceUsdCents + debts.bcvReferenceUsdCents;

  return PatrimonioSnapshot(
    realCostUsdCents: realCostUsdCents,
    todayValueUsdCents: todayValueUsdCents,
    unrealizedPnlUsdCents: todayValueUsdCents - realCostUsdCents,
    bcvReferenceUsdCents: bcvReferenceUsdCents,
    hasMissingRate: snapshot.hasMissingRate,
    accountGroups: snapshot.accountGroups,
    envelopes: snapshot.envelopes,
  );
});

EnvelopeRoleView _mapRole(EnvelopeRole role) => switch (role) {
  EnvelopeRole.none => EnvelopeRoleView.user,
  EnvelopeRole.stage => EnvelopeRoleView.stage,
  EnvelopeRole.differential => EnvelopeRoleView.differential,
  EnvelopeRole.adjustments => EnvelopeRoleView.adjustments,
  EnvelopeRole.opening => EnvelopeRoleView.opening,
};

FundingTargetView _mapTarget(contabilidad.FundingTarget target) =>
    switch (target) {
      contabilidad.NoTarget() => const NoTargetView(),
      contabilidad.Cap(:final amountUsd) => CapView(amountUsd: amountUsd),
      contabilidad.GoalLine(:final amountUsd, :final dueDate) => GoalLineView(
        amountUsd: amountUsd,
        dueDate: dueDate,
      ),
    };
