import 'package:decimal/decimal.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:contabilidad/domain/ports/ledger_projections.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/application/ledger/exceptions.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/catalog/exceptions.dart';

class RecordRealization {
  final RecordTransaction _record;
  final CatalogRepository _catalog;
  final LedgerProjections _projections;

  RecordRealization({
    required RecordTransaction record,
    required CatalogRepository catalog,
    required LedgerProjections projections,
  }) : _record = record,
       _catalog = catalog,
       _projections = projections;

  /// Disposes a foreign-currency account balance via an expense envelope.
  Future<void> foreignCurrencyExpense({
    required EventId eventId,
    required String deviceId,
    required AccountId accountId,
    required EnvelopeId destinationEnvelopeId,
    required Money nativeAmount,
    required Decimal currentRate,
    DomainTimestamp? occurredAt,
  }) async {
    final account = _catalog.getAccount(accountId);
    if (account == null) {
      throw TargetNotFound('Account not found: $accountId');
    }
    if (account.nativeCurrency == CurrencyCode('USD')) {
      throw IncompatibleCurrency(
        'This factory is for foreign currency, not USD.',
      );
    }

    final destinationEnvelope = _catalog.getEnvelope(destinationEnvelopeId);
    if (destinationEnvelope == null) {
      throw TargetNotFound(
        'Destination envelope not found: $destinationEnvelopeId',
      );
    }

    final balance = _projections.accountBalance(accountId);
    if (nativeAmount.amount > balance.native.amount) {
      throw InsufficientBalance('Amount to dispose exceeds account balance');
    }

    final decAmount = Decimal.fromBigInt(nativeAmount.amount);
    final marketValue = (decAmount / currentRate).round().toInt();
    final rateRef =
        '${currentRate.toStringAsFixed(2)} ${nativeAmount.currency.value}/USD';

    await _performDisposal(
      eventId: eventId,
      deviceId: deviceId,
      type: 'ForeignCurrencyExpense',
      sourceAccountId: accountId,
      nativeAmount: nativeAmount,
      costBasis: balance.baseCostOf(nativeAmount.amount),
      observedUsdValue: marketValue,
      destinationPosting: Posting(
        target: EnvelopeTarget(destinationEnvelopeId),
        amountNative: Money(
          amount: BigInt.from(-marketValue),
          currency: CurrencyCode('USD'),
        ),
        currency: CurrencyCode('USD'),
        amountUsd: -marketValue,
        rateRef: rateRef,
      ),
      occurredAt: occurredAt,
    );
  }

  /// Disposes a foreign-currency account balance converting it to a USD account.
  /// Uses the observed USD received (not an inferred rate) for the accounting.
  Future<void> disposalConversion({
    required EventId eventId,
    required String deviceId,
    required AccountId sourceForeignAccountId,
    required AccountId destinationUsdAccountId,
    required Money nativeAmount,
    required Money usdAmountReceived,
    required String rateRef,
    DomainTimestamp? occurredAt,
  }) async {
    final sourceAccount = _catalog.getAccount(sourceForeignAccountId);
    if (sourceAccount == null) {
      throw TargetNotFound('Source account not found: $sourceForeignAccountId');
    }
    if (sourceAccount.nativeCurrency == CurrencyCode('USD')) {
      throw IncompatibleCurrency(
        'Source account must be foreign currency, not USD.',
      );
    }

    final destinationAccount = _catalog.getAccount(destinationUsdAccountId);
    if (destinationAccount == null) {
      throw TargetNotFound(
        'Destination account not found: $destinationUsdAccountId',
      );
    }
    if (destinationAccount.nativeCurrency != CurrencyCode('USD')) {
      throw IncompatibleCurrency('Destination account must be USD.');
    }

    final balance = _projections.accountBalance(sourceForeignAccountId);
    if (nativeAmount.amount > balance.native.amount) {
      throw InsufficientBalance('Amount to dispose exceeds account balance');
    }

    final observedValue = usdAmountReceived.amount.toInt();

    await _performDisposal(
      eventId: eventId,
      deviceId: deviceId,
      type: 'DisposalConversion',
      sourceAccountId: sourceForeignAccountId,
      nativeAmount: nativeAmount,
      costBasis: balance.baseCostOf(nativeAmount.amount),
      observedUsdValue: observedValue,
      destinationPosting: Posting(
        target: AccountTarget(destinationUsdAccountId),
        amountNative: usdAmountReceived,
        currency: CurrencyCode('USD'),
        amountUsd: observedValue,
        rateRef: rateRef,
      ),
      occurredAt: occurredAt,
    );
  }

  /// Sells a crypto asset to a USD account using the observed proceeds.
  Future<void> cryptoSale({
    required EventId eventId,
    required String deviceId,
    required AccountId cryptoAccountId,
    required AccountId destinationUsdAccountId,
    required Money quantity,
    required Money usdAmountReceived,
    required String rateRef,
    DomainTimestamp? occurredAt,
  }) async {
    final cryptoAccount = _catalog.getAccount(cryptoAccountId);
    if (cryptoAccount == null) {
      throw TargetNotFound('Crypto account not found: $cryptoAccountId');
    }
    if (cryptoAccount.nativeCurrency == CurrencyCode('USD')) {
      throw IncompatibleCurrency('Crypto account cannot be USD.');
    }

    final destinationAccount = _catalog.getAccount(destinationUsdAccountId);
    if (destinationAccount == null) {
      throw TargetNotFound(
        'Destination account not found: $destinationUsdAccountId',
      );
    }
    if (destinationAccount.nativeCurrency != CurrencyCode('USD')) {
      throw IncompatibleCurrency('Destination account must be USD.');
    }

    final balance = _projections.accountBalance(cryptoAccountId);
    if (quantity.amount > balance.native.amount) {
      throw InsufficientBalance('Quantity to sell exceeds account balance');
    }

    final observedValue = usdAmountReceived.amount.toInt();

    await _performDisposal(
      eventId: eventId,
      deviceId: deviceId,
      type: 'CryptoSale',
      sourceAccountId: cryptoAccountId,
      nativeAmount: quantity,
      costBasis: balance.baseCostOf(quantity.amount),
      observedUsdValue: observedValue,
      destinationPosting: Posting(
        target: AccountTarget(destinationUsdAccountId),
        amountNative: usdAmountReceived,
        currency: CurrencyCode('USD'),
        amountUsd: observedValue,
        rateRef: rateRef,
      ),
      occurredAt: occurredAt,
    );
  }

  /// Single implementation shared by all three public faces.
  /// Generates the canonical 3-posting realization pattern:
  ///   −A asset (cost_basis), destination (observed_value), ±E Differential (delta).
  Future<void> _performDisposal({
    required EventId eventId,
    required String deviceId,
    required String type,
    required AccountId sourceAccountId,
    required Money nativeAmount,
    required int costBasis,
    required int observedUsdValue,
    required Posting destinationPosting,
    DomainTimestamp? occurredAt,
  }) async {
    final differentialEnvelopeId = _catalog.getSystemEnvelope(
      EnvelopeRole.differential,
    );
    final delta = observedUsdValue - costBasis;

    final postings = [
      Posting(
        target: AccountTarget(sourceAccountId),
        amountNative: Money(
          amount: -nativeAmount.amount,
          currency: nativeAmount.currency,
        ),
        currency: nativeAmount.currency,
        amountUsd: -costBasis,
      ),
      destinationPosting,
      Posting(
        target: EnvelopeTarget(differentialEnvelopeId),
        amountNative: Money(
          amount: BigInt.from(delta),
          currency: CurrencyCode('USD'),
        ),
        currency: CurrencyCode('USD'),
        amountUsd: delta,
      ),
    ];

    final now = DateTime.now().toUtc();
    final metadata = TransactionMetadata(
      eventId: eventId,
      type: type,
      occurredAt: occurredAt ?? DomainTimestamp(now),
      recordedAt: DomainTimestamp(now),
      deviceId: deviceId,
      schemaVersion: 1,
    );

    await _record(postings: postings, metadata: metadata);
  }
}
