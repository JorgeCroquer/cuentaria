import 'package:shared_kernel/shared_kernel.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
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

    final projectedBalance = _projections.accountBalance(accountId);
    final deltaNative =
        realNativeBalance.amount - projectedBalance.native.amount;

    if (deltaNative == BigInt.zero) {
      throw AdjustmentWithNoDifference();
    }

    if (deltaNative > BigInt.zero &&
        account.nativeCurrency != CurrencyCode('USD')) {
      throw ForeignCurrencyPositiveAdjustmentNotAllowed();
    }

    final int amountUsd;
    if (account.nativeCurrency == CurrencyCode('USD')) {
      amountUsd = deltaNative.toInt();
    } else {
      final costBasis = projectedBalance.baseCostOf(deltaNative.abs());
      amountUsd = -costBasis;
    }

    final adjustmentsId = _catalog.getSystemEnvelope(EnvelopeRole.adjustments);

    final postings = [
      Posting(
        target: AccountTarget(accountId),
        amountNative: Money(
          amount: deltaNative,
          currency: account.nativeCurrency,
        ),
        currency: account.nativeCurrency,
        amountUsd: amountUsd,
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
