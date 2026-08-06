import 'package:contabilidad/application/catalog/create_account.dart';
import 'package:decimal/decimal.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/domain/rate_observation.dart';
import 'package:tasas/domain/rate_series.dart';

const _paraleloSource = 'manual:paralelo';

/// Composes [CreateAccount] with [RateSeries] (ADR-0005 app-shell
/// composition — contabilidad may not import tasas' `domain/`): the opening
/// rate the account form already asks for (U1-13) is also appended as a
/// parallel-rate observation, so a fresh install doesn't hit
/// `RateNotAvailable` on the very first Bs expense (#112).
///
/// The observation is dated to [occurredAt] — the fact date of the opening,
/// which may be retroactive — never to "now", so a backdated opening never
/// masquerades as today's rate.
///
/// When [suggestedRate] is given (the Rate Resolution Chain's proposal,
/// #166) and [openingBalanceRate] matches it verbatim, no observation is
/// appended: the user accepted the automatic rate, they didn't type one, so
/// fabricating a `manual:paralelo` observation would outrank the real
/// automatic source for the rest of the day (#174, ADR-0020 §S1-6).
class CreateAccountWithRate {
  final CreateAccount _createAccount;
  final RateSeries _rateSeries;

  CreateAccountWithRate({
    required CreateAccount createAccount,
    required RateSeries rateSeries,
  }) : _createAccount = createAccount,
       _rateSeries = rateSeries;

  Future<AccountId> call({
    required String name,
    required CurrencyCode nativeCurrency,
    String? colorHex,
    Money? openingBalance,
    int? openingBalanceUsd,
    Decimal? openingBalanceRate,
    Decimal? suggestedRate,
    required EventId eventId,
    required String deviceId,
    DomainTimestamp? occurredAt,
  }) async {
    final id = await _createAccount(
      name: name,
      nativeCurrency: nativeCurrency,
      colorHex: colorHex,
      openingBalance: openingBalance,
      openingBalanceUsd: openingBalanceUsd,
      openingBalanceRate: openingBalanceRate,
      eventId: eventId,
      deviceId: deviceId,
      occurredAt: occurredAt,
    );

    if (nativeCurrency != CurrencyCode('USD') &&
        openingBalanceRate != null &&
        openingBalanceRate != suggestedRate) {
      await _rateSeries.append(
        RateObservation(
          currency: nativeCurrency,
          nativePerUsd: openingBalanceRate,
          observedAt: occurredAt?.value ?? DateTime.now().toUtc(),
          source: _paraleloSource,
        ),
      );
    }

    return id;
  }
}
