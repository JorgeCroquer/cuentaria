import 'package:equatable/equatable.dart';
import 'package:shared_kernel/shared_kernel.dart';

/// Patrimonio-owned read view of an Account (ADR-0005): a context never
/// imports another's `domain/`, so the engine takes only this — app-layer
/// wiring maps `contabilidad`'s Account + AccountBalance into it.
class AccountView extends Equatable {
  final AccountId id;
  final CurrencyCode currency;
  final BigInt nativeMinorAmount;
  final int realCostUsdCents;
  final bool isArchived;

  const AccountView({
    required this.id,
    required this.currency,
    required this.nativeMinorAmount,
    required this.realCostUsdCents,
    required this.isArchived,
  });

  @override
  List<Object?> get props => [
    id,
    currency,
    nativeMinorAmount,
    realCostUsdCents,
    isArchived,
  ];
}
