import 'package:decimal/decimal.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/catalog/exceptions.dart';

/// Posts an Income (U1, #97/#119; ADR-0018): a USD account posts its amount
/// as-is; a foreign currency account is valued against [currentRate] — the
/// observed parallel rate, never a stored/declared one — with a single
/// rounding, mirroring `RecordRealization.foreignCurrencyExpense`. Unlike a
/// disposal, money coming in was never held before, so there is nothing to
/// split into covered/excess and no Differential posting: the envelope
/// simply stages the resulting USD equivalent.
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
    Decimal? currentRate,
  }) async {
    final account = _catalog.getAccount(accountId);
    if (account == null) {
      throw TargetNotFound('Account not found: $accountId');
    }

    if (amount.amount <= BigInt.zero) {
      throw ArgumentError('Amount must be strictly positive.');
    }

    final isUsd = account.nativeCurrency == CurrencyCode('USD');
    if (isUsd && currentRate != null) {
      throw ArgumentError('A USD account is not valued against a rate.');
    }
    if (!isUsd && currentRate == null) {
      throw ArgumentError(
        'Foreign currency income requires the observed parallel rate.',
      );
    }

    final targetEnvelopeId =
        envelopeId ?? _catalog.getSystemEnvelope(EnvelopeRole.stage);

    final List<Posting> postings;
    if (isUsd) {
      final amountUsd = amount.amount.toInt();
      postings = [
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
    } else {
      final amountUsd =
          (Decimal.fromBigInt(amount.amount) / currentRate!).round().toInt();
      final rateRef =
          '${currentRate.toStringAsFixed(2)} ${amount.currency.value}/USD';
      postings = [
        Posting(
          target: AccountTarget(accountId),
          amountNative: amount,
          currency: amount.currency,
          amountUsd: amountUsd,
          rateRef: rateRef,
        ),
        Posting(
          target: EnvelopeTarget(targetEnvelopeId),
          amountNative: Money(
            amount: BigInt.from(amountUsd),
            currency: CurrencyCode('USD'),
          ),
          currency: CurrencyCode('USD'),
          amountUsd: amountUsd,
        ),
      ];
    }

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
