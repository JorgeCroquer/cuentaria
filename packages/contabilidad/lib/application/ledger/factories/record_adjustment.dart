import 'package:decimal/decimal.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/split_balance.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:contabilidad/domain/ports/ledger_projections.dart';
import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/application/ledger/exceptions.dart';
import 'package:contabilidad/application/catalog/exceptions.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';

class RecordAdjustment {
  final RecordTransaction _record;
  final LedgerProjections _projections;
  final CatalogRepository _catalog;

  RecordAdjustment({
    required RecordTransaction record,
    required LedgerProjections projections,
    required CatalogRepository catalog,
  }) : _record = record,
       _projections = projections,
       _catalog = catalog;

  Future<void> call({
    required EventId eventId,
    required String deviceId,
    required AccountId accountId,
    required Money realNativeBalance,
    DomainTimestamp? occurredAt,
    Decimal? rate,
  }) async {
    final account = _catalog.getAccount(accountId);
    if (account == null) {
      throw TargetNotFound('Account not found: $accountId');
    }

    if (realNativeBalance.currency != account.nativeCurrency) {
      throw ArgumentError(
        'Real balance currency must match the account native currency.',
      );
    }

    final isUsd = account.nativeCurrency == CurrencyCode('USD');
    if (isUsd && rate != null) {
      throw ArgumentError('A USD account is not valued against a rate.');
    }

    final projectedBalance = _projections.accountBalance(accountId);
    final deltaNative =
        realNativeBalance.amount - projectedBalance.native.amount;

    if (deltaNative == BigInt.zero) {
      throw AdjustmentWithNoDifference();
    }

    final int amountUsd;
    if (isUsd) {
      amountUsd = deltaNative.toInt();
    } else if (deltaNative > BigInt.zero) {
      // Surplus in a foreign currency account: no cost basis was ever held
      // for it, so it's valued with the latest parallel Rate Observation
      // (ADR-0018 §1, ADR-0019 §4).
      if (rate == null) {
        throw ArgumentError(
          'A positive adjustment on a foreign currency account requires '
          'the observed parallel rate.',
        );
      }
      amountUsd = (Decimal.fromBigInt(deltaNative) / rate).round().toInt();
    } else {
      // Disposal, possibly crossing the known balance into an overdraft
      // (ADR-0017 "sobregiro registrable" applied to C3, #209 Debt Account
      // reconciliation): the covered portion keeps its frozen average cost,
      // the excess above it has no cost basis and is valued at the observed
      // rate — same split RecordTransfer already uses for its own excess.
      final split = splitByBalance(projectedBalance, deltaNative.abs());
      final baseCost = projectedBalance.baseCostOf(split.covered);
      if (split.excess == BigInt.zero) {
        amountUsd = -baseCost;
      } else {
        if (rate == null) {
          throw RateRequiredForExcess();
        }
        final excessCost =
            (Decimal.fromBigInt(split.excess) / rate).round().toInt();
        amountUsd = -(baseCost + excessCost);
      }
    }

    final adjustmentsId = _catalog.getSystemEnvelope(EnvelopeRole.adjustments);
    final rateRef =
        rate == null
            ? null
            : '${rate.toStringAsFixed(2)} ${account.nativeCurrency.value}/USD';

    final postings = [
      Posting(
        target: AccountTarget(accountId),
        amountNative: Money(
          amount: deltaNative,
          currency: account.nativeCurrency,
        ),
        currency: account.nativeCurrency,
        amountUsd: amountUsd,
        rateRef: rateRef,
      ),
      Posting(
        target: EnvelopeTarget(adjustmentsId),
        amountNative: Money(
          amount: BigInt.from(amountUsd),
          currency: CurrencyCode('USD'),
        ),
        currency: CurrencyCode('USD'),
        amountUsd: amountUsd,
      ),
    ];

    final now = DateTime.now().toUtc();
    final metadata = TransactionMetadata(
      eventId: eventId,
      type: 'Adjustment',
      occurredAt: occurredAt ?? DomainTimestamp(now),
      recordedAt: DomainTimestamp(now),
      deviceId: deviceId,
      schemaVersion: 1,
    );

    await _record(postings: postings, metadata: metadata);
  }
}
