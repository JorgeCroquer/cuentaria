import 'package:decimal/decimal.dart';
import 'package:shared_kernel/shared_kernel.dart';

import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/application/catalog/exceptions.dart';
import 'package:contabilidad/application/ledger/factories/record_acquisition_conversion.dart';
import 'package:contabilidad/application/ledger/factories/record_transfer.dart';
import 'package:contabilidad/domain/rate_calculator.dart';

/// Derives the right Transaction Factory from whether the two Accounts
/// share a currency (U1, #98): same currency posts a plain transfer,
/// different currencies post a P2P/FX conversion (ADR-0006) — the user
/// never sees this taxonomy, only "Mover". The two-sided form lets the user
/// type either the received amount or the executed rate; whichever is
/// missing is derived via [RateCalculator] and only the resulting native
/// amounts are posted — the rate itself is never stored.
class QuickAddMoverUseCase {
  final RecordTransfer _recordTransfer;
  final RecordAcquisitionConversion _recordAcquisitionConversion;
  final CatalogRepository _catalog;

  QuickAddMoverUseCase({
    required RecordTransfer recordTransfer,
    required RecordAcquisitionConversion recordAcquisitionConversion,
    required CatalogRepository catalog,
  }) : _recordTransfer = recordTransfer,
       _recordAcquisitionConversion = recordAcquisitionConversion,
       _catalog = catalog;

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
      await _recordTransfer(
        eventId: eventId,
        deviceId: deviceId,
        sourceAccountId: sourceAccountId,
        destinationAccountId: destinationAccountId,
        amount: givenAmount,
        occurredAt: occurredAt,
      );
      return;
    }

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
