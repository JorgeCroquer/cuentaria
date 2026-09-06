import 'package:equatable/equatable.dart';

import 'person_debt_point.dart';
import 'report_month.dart';

/// One Debt Point (#265, mirrors [PatrimonioPoint]'s replay shape for
/// ADR-0024 §5-6): [month]'s ledger replayed to its end, Debt Accounts
/// valued through the deudas engine at that cutoff's parallel rate.
/// [personas] holds every counterparty with a nonzero net balance that
/// month — archived accounts still count in the months they held one, and
/// drop out once their balance settles to zero, same replay convention as
/// Patrimonio en el tiempo. [rateSource]/[rateObservedAt] carry the
/// parallel rate actually used to value a non-USD leg, so the UI can
/// announce it even when it is older than the month itself.
class DebtPoint extends Equatable {
  final ReportMonth month;
  final List<PersonDebtPoint> personas;
  final String? rateSource;
  final DateTime? rateObservedAt;

  const DebtPoint({
    required this.month,
    required this.personas,
    this.rateSource,
    this.rateObservedAt,
  });

  @override
  List<Object?> get props => [month, personas, rateSource, rateObservedAt];
}
