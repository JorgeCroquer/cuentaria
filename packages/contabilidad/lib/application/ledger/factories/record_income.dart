import 'package:shared_kernel/shared_kernel.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/ledger/exceptions.dart';
import 'package:contabilidad/application/catalog/exceptions.dart';

class RecordIncome {
  final RecordTransaction _record;
  final CatalogRepository _catalog;

  RecordIncome({
    required RecordTransaction record,
    required CatalogRepository catalog,
  }) : _record = record,
       _catalog = catalog;

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

    if (account.nativeCurrency != CurrencyCode('USD')) {
      throw UsdOnlyOperation();
    }

    final targetEnvelopeId =
        envelopeId ?? _catalog.getSystemEnvelope(EnvelopeRole.stage);

    if (amount.amount <= BigInt.zero) {
      throw ArgumentError('Amount must be strictly positive.');
    }

    final amountUsd = amount.amount.toInt();

    final postings = [
      Posting(
        target: AccountTarget(accountId),
        amountNative: amount,
        currency: amount.currency,
        amountUsd: amountUsd,
      ),
      Posting(
        target: EnvelopeTarget(targetEnvelopeId),
        amountNative: amount,
        currency: amount.currency,
        amountUsd: amountUsd,
      ),
    ];

    final now = DateTime.now().toUtc();
    final metadata = TransactionMetadata(
      eventId: eventId,
      type: 'Income',
      occurredAt: occurredAt ?? DomainTimestamp(now),
      recordedAt: DomainTimestamp(now),
      deviceId: deviceId,
      schemaVersion: 1,
      source: source,
    );

    await _record(postings: postings, metadata: metadata);
  }
}
