import 'package:equatable/equatable.dart';
import 'package:shared_kernel/shared_kernel.dart';

import 'posting_view.dart';

/// Reportes-owned read view of a Ledger Transaction (ADR-0005): app-layer
/// wiring maps contabilidad's `Transaction` into it. [hasAccountPosting]
/// captures whether the transaction ever touched an Account, the signal
/// [SpendingByEnvelopeEngine] uses to tell an Expense/Income/Adjustment
/// (money crossing into/out of the user's total pool) apart from a
/// Distribution (only Envelope-to-Envelope postings, own pockets, ADR-0024
/// §2) without switching on the event type.
class TransactionView extends Equatable {
  final EventId id;
  final EventId? reverses;
  final bool hasAccountPosting;
  final List<PostingView> envelopePostings;

  const TransactionView({
    required this.id,
    this.reverses,
    required this.hasAccountPosting,
    required this.envelopePostings,
  });

  @override
  List<Object?> get props => [
    id,
    reverses,
    hasAccountPosting,
    envelopePostings,
  ];
}
