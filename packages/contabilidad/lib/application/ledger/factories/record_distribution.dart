import 'package:shared_kernel/shared_kernel.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/application/catalog/exceptions.dart';

class DistributionEntry {
  final EnvelopeId envelopeId;
  final int amountUsd;

  DistributionEntry({required this.envelopeId, required this.amountUsd});
}

class RecordDistribution {
  final RecordTransaction _record;
  final CatalogRepository _catalog;

  RecordDistribution({
    required RecordTransaction record,
    required CatalogRepository catalog,
  }) : _record = record,
       _catalog = catalog;

  Future<void> call({
    required EventId eventId,
    required String deviceId,
    required List<DistributionEntry> entries,
    DomainTimestamp? occurredAt,
  }) async {
    int sum = entries.fold(0, (acc, e) => acc + e.amountUsd);
    if (sum != 0) {
      throw ArgumentError(
        'Distribution entries must sum to 0. Current sum: $sum',
      );
    }

    final postings =
        entries.map((e) {
          final envelope = _catalog.getEnvelope(e.envelopeId);
          if (envelope == null) {
            throw TargetNotFound('Envelope not found: ${e.envelopeId.value}');
          }
          return Posting(
            target: EnvelopeTarget(e.envelopeId),
            amountNative: Money(
              amount: BigInt.from(e.amountUsd),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: e.amountUsd,
          );
        }).toList();

    final now = DateTime.now().toUtc();
    final metadata = TransactionMetadata(
      eventId: eventId,
      type: 'Distribution',
      occurredAt: occurredAt ?? DomainTimestamp(now),
      recordedAt: DomainTimestamp(now),
      deviceId: deviceId,
      schemaVersion: 1,
    );

    await _record(postings: postings, metadata: metadata);
  }
}
