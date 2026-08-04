import 'package:decimal/decimal.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/ports/ledger_projections.dart';
import 'package:contabilidad/domain/split_balance.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/application/ledger/exceptions.dart';
import 'package:contabilidad/application/catalog/exceptions.dart';

/// Posts a Transfer between two Accounts of the same currency (ADR-0018 §3).
/// USD moves at par, exactly the typed amount. A non-USD currency moves the
/// proportional frozen cost of the covered portion (`AccountBalance.
/// baseCostOf`, ADR-0017's zero-native rule included) and values any excess
/// above the known balance at [parallelRate] — the series rate, since a
/// transfer has no execution to observe. Both postings carry the same
/// `amountUsd` (one negated) so relabeling where money sits never realizes
/// P&L: there is no differential posting.
class RecordTransfer {
  final RecordTransaction _record;
  final CatalogRepository _catalog;
  final LedgerProjections _projections;

  RecordTransfer({
    required RecordTransaction record,
    required CatalogRepository catalog,
    required LedgerProjections projections,
  }) : _record = record,
       _catalog = catalog,
       _projections = projections;

  Future<void> call({
    required EventId eventId,
    required String deviceId,
    required AccountId sourceAccountId,
    required AccountId destinationAccountId,
    required Money amount,
    Decimal? parallelRate,
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

    if (sourceAccountId == destinationAccountId) {
      throw ArgumentError('Source and destination accounts must differ.');
    }

    if (source.nativeCurrency != destination.nativeCurrency) {
      throw CrossCurrencyTransfer();
    }

    if (amount.amount <= BigInt.zero) {
      throw ArgumentError('Amount must be strictly positive.');
    }

    final isUsd = source.nativeCurrency == CurrencyCode('USD');
    if (isUsd && parallelRate != null) {
      throw ArgumentError('A USD transfer is not valued against a rate.');
    }

    final int costUsd;
    String? rateRef;
    if (isUsd) {
      costUsd = amount.amount.toInt();
    } else {
      final balance = _projections.accountBalance(sourceAccountId);
      final split = splitByBalance(balance, amount.amount);
      final baseCost = balance.baseCostOf(split.covered);
      if (split.excess == BigInt.zero) {
        costUsd = baseCost;
      } else {
        if (parallelRate == null) {
          throw RateRequiredForExcess();
        }
        final excessCost =
            (Decimal.fromBigInt(split.excess) / parallelRate).round().toInt();
        costUsd = baseCost + excessCost;
        rateRef =
            '${parallelRate.toStringAsFixed(2)} ${amount.currency.value}/USD';
      }
    }

    final negatedAmount = Money(
      amount: -amount.amount,
      currency: amount.currency,
    );

    final postings = [
      Posting(
        target: AccountTarget(sourceAccountId),
        amountNative: negatedAmount,
        currency: amount.currency,
        amountUsd: -costUsd,
        rateRef: rateRef,
      ),
      Posting(
        target: AccountTarget(destinationAccountId),
        amountNative: amount,
        currency: amount.currency,
        amountUsd: costUsd,
        rateRef: rateRef,
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
