import 'package:shared_kernel/shared_kernel.dart';
import '../transaccion.dart';
import '../saldo_cuenta.dart';

export '../saldo_cuenta.dart';

abstract class LedgerProjections {
  void aplicar(Transaccion event);
  void limpiar();
  SaldoCuenta saldoCuenta(AccountId id);
  int saldoUsdSobre(EnvelopeId id);
}
