import 'package:decimal/decimal.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/ports/ledger_projections.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/catalog/exceptions.dart';

class RecordOpening {
  final RecordTransaction _record;
  final CatalogRepository _catalog;
  final LedgerProjections _projections;

  RecordOpening({
    required RecordTransaction record,
    required CatalogRepository catalog,
    required LedgerProjections projections,
  }) : _record = record,
       _catalog = catalog,
       _projections = projections;

  Future<void> call({
    required EventId eventId,
    required String deviceId,
    required AccountId accountId,
    required Money nativeAmount,
    int? amountUsd,
    Decimal? rate,
    DomainTimestamp? occurredAt,
  }) async {
    final account = _catalog.getAccount(accountId);
    if (account == null) {
      throw TargetNotFound('Account not found: $accountId');
    }

    // Re-opening guard
    final currentBalance = _projections.accountBalance(accountId);
    if (currentBalance.native.amount != BigInt.zero) {
      throw ArgumentError(
        'Account already has a balance and cannot be opened again.',
      );
    }

    if (nativeAmount.currency != account.nativeCurrency) {
      throw ArgumentError(
        'Amount currency must match the account native currency.',
      );
    }

    int usdCostBasis;

    if (account.nativeCurrency == CurrencyCode('USD')) {
      usdCostBasis = nativeAmount.amount.toInt();
    } else {
      if (amountUsd != null) {
        usdCostBasis = amountUsd;
      } else if (rate != null) {
        final decAmount = Decimal.fromBigInt(nativeAmount.amount);
        usdCostBasis = (decAmount / rate).round().toInt();
      } else {
        throw ArgumentError(
          'Foreign currency accounts require either amountUsd or rate.',
        );
      }
    }

    final openingEnvelopeId = _catalog.getSystemEnvelope(EnvelopeRole.opening);

    final postings = [
      Posting(
        target: AccountTarget(accountId),
        amountNative: nativeAmount,
        currency: nativeAmount.currency,
        amountUsd: usdCostBasis,
        rateRef:
            rate != null
                ? '${rate.toStringAsFixed(2)} ${nativeAmount.currency.value}/USD'
                : null,
      ),
      Posting(
        target: EnvelopeTarget(openingEnvelopeId),
        amountNative: Money(
          amount: BigInt.from(usdCostBasis),
          currency: CurrencyCode('USD'),
        ),
        currency: CurrencyCode('USD'),
        amountUsd: usdCostBasis,
      ),
    ];

    final now = DateTime.now().toUtc();
    final metadata = TransactionMetadata(
      eventId: eventId,
      type: 'Opening',
      occurredAt: occurredAt ?? DomainTimestamp(now),
      recordedAt: DomainTimestamp(now),
      deviceId: deviceId,
      schemaVersion: 1,
    );

    await _record(postings: postings, metadata: metadata);
  }
}
