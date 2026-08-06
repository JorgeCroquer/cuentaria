import 'package:decimal/decimal.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/application/rate_resolution_service.dart';
import 'package:tasas/domain/rate_series.dart';

import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/application/catalog/exceptions.dart';
import 'package:contabilidad/application/ledger/factories/record_acquisition_conversion.dart';
import 'package:contabilidad/application/ledger/factories/record_realization.dart';
import 'package:contabilidad/application/ledger/factories/record_transfer.dart';
import 'package:contabilidad/domain/rate_calculator.dart';

/// Derives the right Transaction Factory from the currencies of the two
/// Accounts (U1-14, #98/#116): same currency posts a plain transfer (valued
/// against the latest parallel Rate Observation when it's a non-USD excess
/// above the known balance, ADR-0018 §3); USD origin -> foreign destination
/// posts a P2P/FX acquisition (ADR-0006); foreign origin -> USD destination
/// posts a realization/disposal (ADR-0017/0018) — the user never sees this
/// taxonomy, only "Mover". The two-sided form lets the user type either the
/// received amount or the executed rate; whichever is missing is derived via
/// [RateCalculator] and only the resulting amounts are posted — the rate
/// itself is never stored.
class QuickAddMoverUseCase {
  final RecordTransfer _recordTransfer;
  final RecordAcquisitionConversion _recordAcquisitionConversion;
  final RecordRealization _recordRealization;
  final CatalogRepository _catalog;
  final RateSeries _rateSeries;

  QuickAddMoverUseCase({
    required RecordTransfer recordTransfer,
    required RecordAcquisitionConversion recordAcquisitionConversion,
    required RecordRealization recordRealization,
    required CatalogRepository catalog,
    required RateSeries rateSeries,
  }) : _recordTransfer = recordTransfer,
       _recordAcquisitionConversion = recordAcquisitionConversion,
       _recordRealization = recordRealization,
       _catalog = catalog,
       _rateSeries = rateSeries;

  Future<void> call({
    required EventId eventId,
    required String deviceId,
    required AccountId sourceAccountId,
    required AccountId destinationAccountId,
    required Money givenAmount,
    Money? receivedAmount,
    Decimal? rate,
    DomainTimestamp? occurredAt,
  }) async {
    final source = _catalog.getAccount(sourceAccountId);
    if (source == null) {
      throw TargetNotFound('Source account not found: $sourceAccountId');
    }
    final destination = _catalog.getAccount(destinationAccountId);
    if (destination == null) {
      throw TargetNotFound(
        'Destination account not found: $destinationAccountId',
      );
    }

    if (source.nativeCurrency == destination.nativeCurrency) {
      Decimal? parallelRate;
      if (source.nativeCurrency != CurrencyCode('USD')) {
        final resolution = await RateResolutionService(_rateSeries)(
          source.nativeCurrency,
        );
        parallelRate = resolution?.nativePerUsd;
      }

      await _recordTransfer(
        eventId: eventId,
        deviceId: deviceId,
        sourceAccountId: sourceAccountId,
        destinationAccountId: destinationAccountId,
        amount: givenAmount,
        parallelRate: parallelRate,
        occurredAt: occurredAt,
      );
      return;
    }

    final usdCurrency = CurrencyCode('USD');
    if (source.nativeCurrency != usdCurrency &&
        destination.nativeCurrency == usdCurrency) {
      final Money resolvedReceivedUsd;
      if (receivedAmount != null) {
        resolvedReceivedUsd = receivedAmount;
      } else if (rate != null) {
        resolvedReceivedUsd = Money(
          amount: RateCalculator.deriveUsdCents(
            nativeCents: givenAmount.amount,
            rate: rate,
          ),
          currency: usdCurrency,
        );
      } else {
        throw ArgumentError(
          'Different-currency movers require either a received amount or a '
          'rate.',
        );
      }

      final effectiveRate =
          rate ??
          RateCalculator.deriveRate(
            usdCents: resolvedReceivedUsd.amount,
            nativeCents: givenAmount.amount,
          );

      await _recordRealization.disposalConversion(
        eventId: eventId,
        deviceId: deviceId,
        sourceForeignAccountId: sourceAccountId,
        destinationUsdAccountId: destinationAccountId,
        nativeAmount: givenAmount,
        usdAmountReceived: resolvedReceivedUsd,
        rateRef:
            '${effectiveRate.toStringAsFixed(2)} '
            '${source.nativeCurrency.value}/USD',
        occurredAt: occurredAt,
      );
      return;
    }

    // USD origin -> foreign destination (AcquisitionConversion), or foreign
    // -> different foreign (ADR-0018 §5, unreachable from the UI chips):
    // RecordAcquisitionConversion rejects a non-USD source with
    // UsdOnlyOperation before touching any amount.
    final Money resolvedReceived;
    if (receivedAmount != null) {
      resolvedReceived = receivedAmount;
    } else if (rate != null) {
      resolvedReceived = Money(
        amount: RateCalculator.deriveNativeCents(
          usdCents: givenAmount.amount,
          rate: rate,
        ),
        currency: destination.nativeCurrency,
      );
    } else {
      throw ArgumentError(
        'Different-currency movers require either a received amount or a '
        'rate.',
      );
    }

    final effectiveRate =
        rate ??
        RateCalculator.deriveRate(
          usdCents: givenAmount.amount,
          nativeCents: resolvedReceived.amount,
        );

    await _recordAcquisitionConversion(
      eventId: eventId,
      deviceId: deviceId,
      sourceUsdAccountId: sourceAccountId,
      destinationForeignAccountId: destinationAccountId,
      usdAmount: givenAmount,
      foreignAmountReceived: resolvedReceived,
      rateRef:
          '${effectiveRate.toStringAsFixed(2)} '
          '${destination.nativeCurrency.value}/USD',
      occurredAt: occurredAt,
    );
  }
}
