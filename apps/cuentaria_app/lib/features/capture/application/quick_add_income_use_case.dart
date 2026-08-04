import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/application/catalog/exceptions.dart';
import 'package:contabilidad/application/ledger/factories/record_income.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/domain/rate_series.dart';

import 'rate_exceptions.dart';

const _paraleloSource = 'manual:paralelo';

/// Derives the right valuation for Ingreso from the destination Account's
/// currency (U1, #97/#119; ADR-0018): USD posts the income as-is, foreign
/// currency values it against the latest parallel Rate Observation — the
/// user never sees this taxonomy, only the resulting income. Lives in the
/// app layer (not `contabilidad`) because it composes contabilidad's
/// [RecordIncome] with tasas' [RateSeries], and `contabilidad` may not
/// import another context's `domain/` (ADR-0005).
class QuickAddIncomeUseCase {
  final RecordIncome _recordIncome;
  final CatalogRepository _catalog;
  final RateSeries _rateSeries;

  QuickAddIncomeUseCase({
    required RecordIncome recordIncome,
    required CatalogRepository catalog,
    required RateSeries rateSeries,
  }) : _recordIncome = recordIncome,
       _catalog = catalog,
       _rateSeries = rateSeries;

  Future<void> call({
    required EventId eventId,
    required String deviceId,
    required AccountId accountId,
    required Money amount,
    required String source,
    EnvelopeId? envelopeId,
    DomainTimestamp? occurredAt,
  }) async {
    final account = _catalog.getAccount(accountId);
    if (account == null) {
      throw TargetNotFound('Account not found: $accountId');
    }

    if (account.nativeCurrency == CurrencyCode('USD')) {
      await _recordIncome(
        eventId: eventId,
        deviceId: deviceId,
        accountId: accountId,
        amount: amount,
        source: source,
        envelopeId: envelopeId,
        occurredAt: occurredAt,
      );
      return;
    }

    final observation = await _rateSeries.latestFor(
      account.nativeCurrency,
      source: _paraleloSource,
    );
    if (observation == null) {
      throw RateNotAvailable(
        'No parallel rate observed for ${account.nativeCurrency.value}',
      );
    }

    await _recordIncome(
      eventId: eventId,
      deviceId: deviceId,
      accountId: accountId,
      amount: amount,
      source: source,
      envelopeId: envelopeId,
      occurredAt: occurredAt,
      currentRate: observation.nativePerUsd,
    );
  }
}
