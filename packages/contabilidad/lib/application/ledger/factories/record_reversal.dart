import 'package:shared_kernel/shared_kernel.dart';
import 'package:contabilidad/domain/ports/event_store.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:contabilidad/application/ledger/exceptions.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';

class RecordReversal {
  final RecordTransaction _record;
  final EventStore _store;

  RecordReversal({required RecordTransaction record, required EventStore store})
    : _record = record,
      _store = store;

  Future<void> call({
    required EventId eventId,
    required String deviceId,
    required EventId originalEventId,
    DomainTimestamp? occurredAt,
  }) async {
    final original = await _store.get(originalEventId);
    if (original == null) {
      throw TransactionNotFound(
        'Original transaction not found: $originalEventId',
      );
    }

    if (await _store.hasReversal(originalEventId)) {
      throw TransactionAlreadyReversed(
        'Transaction has already been reversed: $originalEventId',
      );
    }

    final invertedPostings =
        original.postings.map((p) {
          return Posting(
            target: p.target,
            amountNative: Money(
              amount: -p.amountNative.amount,
              currency: p.amountNative.currency,
            ),
            currency: p.currency,
            amountUsd: -p.amountUsd,
            rateRef: p.rateRef,
          );
        }).toList();

    final now = DateTime.now().toUtc();
    final metadata = TransactionMetadata(
      eventId: eventId,
      type: 'Reversal',
      occurredAt: occurredAt ?? DomainTimestamp(now),
      recordedAt: DomainTimestamp(now),
      deviceId: deviceId,
      schemaVersion: 1,
      reverses: originalEventId,
    );

    await _record(postings: invertedPostings, metadata: metadata);
  }
}
