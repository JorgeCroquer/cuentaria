import 'package:shared_kernel/shared_kernel.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/application/ledger/exceptions.dart';
import 'package:contabilidad/application/catalog/exceptions.dart';

class RecordUsdExpense {
  final RecordTransaction _record;
  final CatalogRepository _catalog;

  RecordUsdExpense({
    required RecordTransaction record,
    required CatalogRepository catalog,
  }) : _record = record,
       _catalog = catalog;

  Future<void> call({
    required EventId eventId,
    required String deviceId,
    required AccountId accountId,
    required EnvelopeId envelopeId,
    required Money amount,
    DomainTimestamp? occurredAt,
  }) async {
    final account = _catalog.getAccount(accountId);
    if (account == null) {
      throw TargetNotFound('Account not found: $accountId');
    }

    if (account.nativeCurrency != CurrencyCode('USD')) {
      throw UsdOnlyOperation();
    }

    if (amount.amount <= BigInt.zero) {
      throw ArgumentError('Amount must be strictly positive.');
    }

    final amountUsd = amount.amount.toInt();
    final negatedAmount = Money(amount: -amount.amount, currency: amount.currency);

    final postings = [
      Posting(
        target: AccountTarget(accountId),
        amountNative: negatedAmount,
        currency: amount.currency,
        amountUsd: -amountUsd,
      ),
      Posting(
        target: EnvelopeTarget(envelopeId),
        amountNative: negatedAmount,
        currency: amount.currency,
        amountUsd: -amountUsd,
      ),
    ];

    final now = DateTime.now().toUtc();
    final metadata = TransactionMetadata(
      eventId: eventId,
      type: 'Expense',
      occurredAt: occurredAt ?? DomainTimestamp(now),
      recordedAt: DomainTimestamp(now),
      deviceId: deviceId,
      schemaVersion: 1,
    );

    await _record(postings: postings, metadata: metadata);
  }
}
