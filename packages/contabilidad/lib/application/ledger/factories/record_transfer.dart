import 'package:shared_kernel/shared_kernel.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/application/ledger/exceptions.dart';
import 'package:contabilidad/application/catalog/exceptions.dart';

class RecordTransfer {
  final RecordTransaction _record;
  final CatalogRepository _catalog;

  RecordTransfer({
    required RecordTransaction record,
    required CatalogRepository catalog,
  }) : _record = record,
       _catalog = catalog;

  Future<void> call({
    required EventId eventId,
    required String deviceId,
    required AccountId sourceAccountId,
    required AccountId destinationAccountId,
    required Money amount,
    DomainTimestamp? occurredAt,
  }) async {
    final source = _catalog.getAccount(sourceAccountId);
    if (source == null) {
      throw TargetNotFound('Source account not found: $sourceAccountId');
    }

    final destination = _catalog.getAccount(destinationAccountId);
    if (destination == null) {
      throw TargetNotFound('Destination account not found: $destinationAccountId');
    }

    if (source.nativeCurrency != destination.nativeCurrency) {
      throw CrossCurrencyTransfer();
    }

    if (source.nativeCurrency != CurrencyCode('USD')) {
      throw UsdOnlyOperation();
    }

    if (amount.amount <= BigInt.zero) {
      throw ArgumentError('Amount must be strictly positive.');
    }

    final amountUsd = amount.amount.toInt();
    final negatedAmount = Money(amount: -amount.amount, currency: amount.currency);

    final postings = [
      Posting(
        target: AccountTarget(sourceAccountId),
        amountNative: negatedAmount,
        currency: amount.currency,
        amountUsd: -amountUsd,
      ),
      Posting(
        target: AccountTarget(destinationAccountId),
        amountNative: amount,
        currency: amount.currency,
        amountUsd: amountUsd,
      ),
    ];

    final now = DateTime.now().toUtc();
    final metadata = TransactionMetadata(
      eventId: eventId,
      type: 'Transfer',
      occurredAt: occurredAt ?? DomainTimestamp(now),
      recordedAt: DomainTimestamp(now),
      deviceId: deviceId,
      schemaVersion: 1,
    );

    await _record(postings: postings, metadata: metadata);
  }
}
