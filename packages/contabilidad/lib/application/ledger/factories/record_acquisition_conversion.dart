import 'package:shared_kernel/shared_kernel.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/application/ledger/exceptions.dart';
import 'package:contabilidad/application/catalog/exceptions.dart';

class RecordAcquisitionConversion {
  final RecordTransaction _record;
  final CatalogRepository _catalog;

  RecordAcquisitionConversion({
    required RecordTransaction record,
    required CatalogRepository catalog,
  }) : _record = record,
       _catalog = catalog;

  Future<void> call({
    required EventId eventId,
    required String deviceId,
    required AccountId sourceUsdAccountId,
    required AccountId destinationForeignAccountId,
    required Money usdAmount,
    required Money foreignAmountReceived,
    required String rateRef,
    DomainTimestamp? occurredAt,
  }) async {
    final source = _catalog.getAccount(sourceUsdAccountId);
    if (source == null) {
      throw TargetNotFound(
        'Source account not found: $sourceUsdAccountId',
      );
    }

    final destination = _catalog.getAccount(destinationForeignAccountId);
    if (destination == null) {
      throw TargetNotFound(
        'Destination account not found: $destinationForeignAccountId',
      );
    }

    if (source.nativeCurrency != CurrencyCode('USD')) {
      throw UsdOnlyOperation();
    }

    if (destination.nativeCurrency == CurrencyCode('USD')) {
      throw ArgumentError(
        'Destination account cannot be USD in a foreign currency acquisition.',
      );
    }

    if (usdAmount.amount <= BigInt.zero ||
        foreignAmountReceived.amount <= BigInt.zero) {
      throw ArgumentError('Amounts must be strictly positive.');
    }

    final amountUsdInt = usdAmount.amount.toInt();

    final postings = [
      Posting(
        target: AccountTarget(sourceUsdAccountId),
        amountNative: Money(
          amount: -usdAmount.amount,
          currency: usdAmount.currency,
        ),
        currency: usdAmount.currency,
        amountUsd: -amountUsdInt,
      ),
      Posting(
        target: AccountTarget(destinationForeignAccountId),
        amountNative: foreignAmountReceived,
        currency: foreignAmountReceived.currency,
        amountUsd: amountUsdInt,
        rateRef: rateRef,
      ),
    ];

    final now = DateTime.now().toUtc();
    final metadata = TransactionMetadata(
      eventId: eventId,
      type: 'AcquisitionConversion',
      occurredAt: occurredAt ?? DomainTimestamp(now),
      recordedAt: DomainTimestamp(now),
      deviceId: deviceId,
      schemaVersion: 1,
    );

    await _record(postings: postings, metadata: metadata);
  }
}
