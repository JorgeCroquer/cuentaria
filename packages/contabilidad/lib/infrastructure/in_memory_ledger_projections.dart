import 'package:shared_kernel/shared_kernel.dart';
import '../domain/transaccion.dart';
import '../domain/ports/ledger_projections.dart';
import '../domain/posting_target.dart';

class InMemoryLedgerProjections implements LedgerProjections {
  final Map<AccountId, SaldoCuenta> _cuentas = {};
  final Map<EnvelopeId, int> _sobres = {};

  @override
  void aplicar(Transaccion event) {
    for (final posting in event.postings) {
      final target = posting.target;
      if (target is CuentaTarget) {
        final current =
            _cuentas[target.accountId] ??
            SaldoCuenta(
              native: Money(amount: BigInt.zero, currency: posting.currency),
              usd: 0,
            );

        // Sumamos native
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

        _cuentas[target.accountId] = SaldoCuenta(
          native: newNative,
          usd: current.usd + posting.amountUsd,
        );
      } else if (target is SobreTarget) {
        final current = _sobres[target.envelopeId] ?? 0;
        _sobres[target.envelopeId] = current + posting.amountUsd;
      }
    }
  }

  @override
  void limpiar() {
    _cuentas.clear();
    _sobres.clear();
  }

  @override
  SaldoCuenta saldoCuenta(AccountId id) {
    return _cuentas[id] ??
        SaldoCuenta(
          native: Money(amount: BigInt.zero, currency: CurrencyCode('USD')),
          usd: 0,
        );
  }

  @override
  int saldoUsdSobre(EnvelopeId id) {
    return _sobres[id] ?? 0;
  }
}
