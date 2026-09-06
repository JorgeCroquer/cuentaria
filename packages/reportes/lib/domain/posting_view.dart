import 'package:equatable/equatable.dart';
import 'package:shared_kernel/shared_kernel.dart';

/// One Envelope-dimension posting from a Ledger Transaction, in frozen
/// `amount_usd` cents (ADR-0006) — app-layer wiring drops the Account-side
/// postings and keeps only what [SpendingByEnvelopeEngine] needs.
class PostingView extends Equatable {
  final EnvelopeId envelopeId;
  final int amountUsdCents;

  const PostingView({required this.envelopeId, required this.amountUsdCents});

  @override
  List<Object?> get props => [envelopeId, amountUsdCents];
}
