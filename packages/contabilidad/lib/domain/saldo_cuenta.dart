import 'package:equatable/equatable.dart';
import 'package:shared_kernel/shared_kernel.dart';

class SaldoCuenta extends Equatable {
  final Money native;
  final int usd;

  const SaldoCuenta({required this.native, required this.usd});

  @override
  List<Object?> get props => [native, usd];

  int costoBaseDe(BigInt montoNativeMinor) {
    if (native.amount == BigInt.zero || usd == 0) return 0;

    // Regla de cero-native (C1-6): el último retiro se lleva TODO el costo restante
    if (montoNativeMinor == native.amount) return usd;

    // Proporcional: (saldoUsdCents * montoNativeMinor) ~/ saldoNativeMinor
    final usdBig = BigInt.from(usd);
    return ((usdBig * montoNativeMinor) ~/ native.amount).toInt();
  }
}
