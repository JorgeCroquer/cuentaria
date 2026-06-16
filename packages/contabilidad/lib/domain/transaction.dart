import 'package:equatable/equatable.dart';
import 'package:event_bus/event_bus.dart';
import 'posting.dart';
import 'posting_target.dart';
import 'transaction_metadata.dart';
import 'transaction_error.dart';

class Transaction extends DomainEvent with EquatableMixin {
  final List<Posting> postings;
  final TransactionMetadata metadata;

  const Transaction._({required this.postings, required this.metadata});

  factory Transaction.create({
    required List<Posting> postings,
    required TransactionMetadata metadata,
  }) {
    if (postings.isEmpty) {
      throw EmptyTransaction();
    }

    int sumAccounts = 0;
    int sumEnvelopes = 0;

    for (final posting in postings) {
      if (posting.dimension == Dimension.account) {
        sumAccounts += posting.amountUsd;
      } else if (posting.dimension == Dimension.envelope) {
        sumEnvelopes += posting.amountUsd;
      }
    }

    if (sumAccounts != sumEnvelopes) {
      throw UnbalancedTransaction();
    }

    return Transaction._(
      postings: List.unmodifiable(postings),
      metadata: metadata,
    );
  }

  @override
  List<Object?> get props => [postings, metadata];
}
