import 'package:equatable/equatable.dart';
import 'package:shared_kernel/shared_kernel.dart';

/// Deudas-owned read view of a Debt Account (ADR-0022, ADR-0005): a context
/// never imports another's `domain/`, so the engine takes only this —
/// app-layer wiring maps contabilidad's Account + AccountBalance into it.
/// [counterpartyName] is the person label (ADR-0022 §1: the person is not an
/// entity, only a tag on the account). [nativeMinorAmount] and
/// [realCostUsdCents] are signed — positive means the person owes the user,
/// negative means the user owes the person (ADR-0022 §2: one type, the sign
/// tells the story).
class DebtAccountView extends Equatable {
  final AccountId id;
  final String counterpartyName;
  final CurrencyCode currency;
  final BigInt nativeMinorAmount;
  final int realCostUsdCents;
  final bool isArchived;

  const DebtAccountView({
    required this.id,
    required this.counterpartyName,
    required this.currency,
    required this.nativeMinorAmount,
    required this.realCostUsdCents,
    required this.isArchived,
  });

  @override
  List<Object?> get props => [
    id,
    counterpartyName,
    currency,
    nativeMinorAmount,
    realCostUsdCents,
    isArchived,
  ];
}
