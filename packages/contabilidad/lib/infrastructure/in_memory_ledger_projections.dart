import 'package:shared_kernel/shared_kernel.dart';
import '../domain/transaction.dart';
import '../domain/ports/ledger_projections.dart';
import '../domain/posting_target.dart';

class InMemoryLedgerProjections implements LedgerProjections {
  final Map<AccountId, AccountBalance> _accounts = {};
  final Map<EnvelopeId, int> _envelopes = {};

  @override
  void apply(Transaction event) {
    for (final posting in event.postings) {
      final target = posting.target;
      if (target is AccountTarget) {
        final current =
            _accounts[target.accountId] ??
            AccountBalance(
              native: Money(amount: BigInt.zero, currency: posting.currency),
              usd: 0,
            );

        // Add native
        if (current.native.amount != BigInt.zero &&
            current.native.currency != posting.currency) {
          throw StateError(
            'Account ${target.accountId.value} already has native balance in '
            '${current.native.currency.value}, cannot add ${posting.currency.value}.',
          );
        }
        final newNative = Money(
          amount: current.native.amount + posting.amountNative.amount,
          currency: posting.currency,
        );

        _accounts[target.accountId] = AccountBalance(
          native: newNative,
          usd: current.usd + posting.amountUsd,
        );
      } else if (target is EnvelopeTarget) {
        final current = _envelopes[target.envelopeId] ?? 0;
        _envelopes[target.envelopeId] = current + posting.amountUsd;
      }
    }
  }

  @override
  void clear() {
    _accounts.clear();
    _envelopes.clear();
  }

  @override
  AccountBalance accountBalance(AccountId id) {
    return _accounts[id] ??
        AccountBalance(
          native: Money(amount: BigInt.zero, currency: CurrencyCode('USD')),
          usd: 0,
        );
  }

  @override
  int envelopeUsdBalance(EnvelopeId id) {
    return _envelopes[id] ?? 0;
  }
}
