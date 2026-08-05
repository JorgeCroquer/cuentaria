import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/application/catalog/exceptions.dart';
import 'package:contabilidad/application/ledger/factories/record_adjustment.dart';
import 'package:contabilidad/domain/ports/ledger_projections.dart';
import 'package:contabilidad/domain/reconciliation/reconciliation_planner.dart';
import 'package:decimal/decimal.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/application/rate_resolution_service.dart';
import 'package:tasas/domain/rate_series.dart';

import '../../capture/application/rate_exceptions.dart';
import 'mark_account_reconciled.dart';

/// Orchestrates the Reconciliation ritual (C3, #147, ADR-0019): resolves the
/// applicable rate, asks the pure [planReconciliation] what to do with the
/// delta, and posts an [RecordAdjustment] for `Absorb` — or for a routed
/// outcome when the user chose the escape hatch ("absorb anyway", ADR-0019
/// §1) via [forceAbsorb]. Lives in the app layer, not `contabilidad`, for
/// the same reason the quick-add capture use cases do: `contabilidad` may
/// not import `tasas`' `domain/` (ADR-0005). Stamps `lastReconciledAt`
/// (#150) whenever it actually posts — never for `NothingToReconcile`.
class ReconcileUseCase {
  final RecordAdjustment _recordAdjustment;
  final CatalogRepository _catalog;
  final LedgerProjections _projections;
  final RateSeries _rateSeries;
  final MarkAccountReconciled _markReconciled;

  ReconcileUseCase({
    required RecordAdjustment recordAdjustment,
    required CatalogRepository catalog,
    required LedgerProjections projections,
    required RateSeries rateSeries,
    required MarkAccountReconciled markReconciled,
  }) : _recordAdjustment = recordAdjustment,
       _catalog = catalog,
       _projections = projections,
       _rateSeries = rateSeries,
       _markReconciled = markReconciled;

  Future<ReconciliationOutcome> call({
    required EventId eventId,
    required String deviceId,
    required AccountId accountId,
    required Money realNativeBalance,
    bool forceAbsorb = false,
    DomainTimestamp? occurredAt,
  }) async {
    final account = _catalog.getAccount(accountId);
    if (account == null) {
      throw TargetNotFound('Account not found: $accountId');
    }

    final isUsd = account.nativeCurrency == CurrencyCode('USD');
    Decimal rate = Decimal.one;
    if (!isUsd) {
      final resolution = await RateResolutionService(_rateSeries)(
        account.nativeCurrency,
      );
      if (resolution == null) {
        throw RateNotAvailable(
          'No parallel rate observed for ${account.nativeCurrency.value}',
        );
      }
      rate = resolution.nativePerUsd;
    }

    final projectedBalance = _projections.accountBalance(accountId);
    final deltaNative =
        realNativeBalance.amount - projectedBalance.native.amount;

    final outcome = planReconciliation(deltaNative: deltaNative, rate: rate);

    if (outcome is Absorb || (outcome is! NothingToReconcile && forceAbsorb)) {
      await _recordAdjustment(
        eventId: eventId,
        deviceId: deviceId,
        accountId: accountId,
        realNativeBalance: realNativeBalance,
        occurredAt: occurredAt,
        rate: isUsd ? null : rate,
      );
      await _markReconciled(accountId, DateTime.now().toUtc());
    }

    return outcome;
  }
}
