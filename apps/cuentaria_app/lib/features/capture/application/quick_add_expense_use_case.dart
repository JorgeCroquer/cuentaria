import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/application/catalog/exceptions.dart';
import 'package:contabilidad/application/ledger/factories/record_realization.dart';
import 'package:contabilidad/application/ledger/factories/record_usd_expense.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/application/rate_resolution_service.dart';
import 'package:tasas/domain/rate_series.dart';

import 'rate_exceptions.dart';

/// Derives the right Transaction Factory from the paying Account's currency
/// (U1, #97): USD posts a plain expense, Bs/foreign posts a realization
/// against the system Differential envelope — the user never sees this
/// taxonomy, only the resulting expense. Lives in the app layer (not
/// `contabilidad`) because it composes contabilidad's factories with tasas'
/// [RateSeries], and `contabilidad` may not import another context's
/// `domain/` (ADR-0005).
class QuickAddExpenseUseCase {
  final RecordUsdExpense _recordUsdExpense;
  final RecordRealization _recordRealization;
  final CatalogRepository _catalog;
  final RateSeries _rateSeries;

  QuickAddExpenseUseCase({
    required RecordUsdExpense recordUsdExpense,
    required RecordRealization recordRealization,
    required CatalogRepository catalog,
    required RateSeries rateSeries,
  }) : _recordUsdExpense = recordUsdExpense,
       _recordRealization = recordRealization,
       _catalog = catalog,
       _rateSeries = rateSeries;

  Future<void> call({
    required EventId eventId,
    required String deviceId,
    required AccountId accountId,
    required EnvelopeId envelopeId,
    required Money amount,
    DomainTimestamp? occurredAt,
    String? note,
  }) async {
    final account = _catalog.getAccount(accountId);
    if (account == null) {
      throw TargetNotFound('Account not found: $accountId');
    }

    if (account.nativeCurrency == CurrencyCode('USD')) {
      await _recordUsdExpense(
        eventId: eventId,
        deviceId: deviceId,
        accountId: accountId,
        envelopeId: envelopeId,
        amount: amount,
        occurredAt: occurredAt,
        memo: note,
      );
      return;
    }

    final resolution = await RateResolutionService(_rateSeries)(
      account.nativeCurrency,
      asOf: occurredAt?.value,
    );
    if (resolution == null) {
      throw RateNotAvailable(
        'No hay tasa paralela registrada para '
        '${account.nativeCurrency.value}',
      );
    }

    await _recordRealization.foreignCurrencyExpense(
      eventId: eventId,
      deviceId: deviceId,
      accountId: accountId,
      destinationEnvelopeId: envelopeId,
      nativeAmount: amount,
      currentRate: resolution.nativePerUsd,
      occurredAt: occurredAt,
      memo: note,
    );
  }
}
