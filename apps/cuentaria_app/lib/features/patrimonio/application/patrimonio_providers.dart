import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/catalog/models/funding_target.dart'
    as contabilidad;
import 'package:contabilidad/domain/transaction.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:patrimonio/patrimonio.dart';
import 'package:shared_kernel/shared_kernel.dart';

import '../../../providers/composition_root.dart';
import '../../../providers/tasas_providers.dart';

const _engine = PatrimonioEngine();
const _bcvSource = 'manual:bcv';
const _paraleloSource = 'manual:paralelo';

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

  final catalog = await ref.watch(catalogRepositoryProvider.future);
  final projections = ref.watch(ledgerProjectionsProvider);
  final series = await ref.watch(rateSeriesProvider.future);

  final accounts = [
    for (final account in catalog.accounts)
      AccountView(
        id: account.id,
        currency: account.nativeCurrency,
        nativeMinorAmount: projections.accountBalance(account.id).native.amount,
        realCostUsdCents: projections.accountBalance(account.id).usd,
        isArchived: account.isArchived,
      ),
  ];

  final usd = CurrencyCode('USD');
  final foreignCurrencies =
      accounts.map((a) => a.currency).where((c) => c != usd).toSet();

  final rates = <CurrencyCode, RateView>{};
  for (final currency in foreignCurrencies) {
    final parallel = await series.latestFor(currency, source: _paraleloSource);
    final bcv = await series.latestFor(currency, source: _bcvSource);
    if (parallel == null && bcv == null) continue;

    rates[currency] = RateView(
      currency: currency,
      parallel:
          parallel == null
              ? null
              : RateObservationView(
                nativePerUsd: parallel.nativePerUsd,
                observedAt: parallel.observedAt,
              ),
      bcv:
          bcv == null
              ? null
              : RateObservationView(
                nativePerUsd: bcv.nativePerUsd,
                observedAt: bcv.observedAt,
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
        ),
  ];

  return _engine(accounts, rates, envelopes, DateTime.now().toUtc());
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
