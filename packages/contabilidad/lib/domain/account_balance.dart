import 'package:equatable/equatable.dart';
import 'package:shared_kernel/shared_kernel.dart';

class AccountBalance extends Equatable {
  final Money native;
  final int usd;

  const AccountBalance({required this.native, required this.usd});

  @override
  List<Object?> get props => [native, usd];

  int baseCostOf(BigInt nativeMinorAmount) {
    if (native.amount == BigInt.zero || usd == 0) return 0;

    // Zero-native rule (C1-6): last withdrawal takes ALL remaining cost basis
    if (nativeMinorAmount == native.amount) return usd;

    // Proportional: (usdBalanceCents * nativeMinorAmount) ~/ nativeBalanceMinor
    final usdBig = BigInt.from(usd);
    return ((usdBig * nativeMinorAmount) ~/ native.amount).toInt();
  }
}
