import 'package:test/test.dart';
import 'package:event_bus/event_bus.dart';
import 'package:shared_kernel/shared_kernel.dart';

import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/application/ledger/factories/record_distribution.dart';
import 'package:contabilidad/application/catalog/exceptions.dart';
import 'package:contabilidad/domain/posting_target.dart';

void main() {
  group('RecordDistribution', () {
    late InMemoryEventStore store;
    late InMemoryLedgerProjections projections;
    late SyncEventBus eventBus;
    late InMemoryCatalogRepository catalog;
    late RecordTransaction recordTransaction;
    late RecordDistribution recordDistribution;

    setUp(() {
      store = InMemoryEventStore();
      projections = InMemoryLedgerProjections();
      eventBus = SyncEventBus();
      catalog = InMemoryCatalogRepository();

      final validator = ReferentialIntegrityValidator(catalog);
      recordTransaction = RecordTransaction(
        store: store,
        projections: projections,
        eventBus: eventBus,
        validator: validator,
      );

      recordDistribution = RecordDistribution(
        record: recordTransaction,
        catalog: catalog,
      );
    });

    test('rejects if entries sum is not exactly 0', () async {
      final envId1 = EnvelopeId('env-1');
      final envId2 = EnvelopeId('env-2');

      catalog.saveEnvelope(
        Envelope(
          id: envId1,
          name: 'Envelope 1',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      catalog.saveEnvelope(
        Envelope(
          id: envId2,
          name: 'Envelope 2',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      // Sum is -100 + 50 = -50 != 0
      final entries = [
        DistributionEntry(envelopeId: envId1, amountUsd: -100),
        DistributionEntry(envelopeId: envId2, amountUsd: 50),
      ];

      await expectLater(
        () => recordDistribution(
          eventId: EventId('evt-1'),
          deviceId: 'dev-1',
          entries: entries,
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(store.events.isEmpty, isTrue);
    });

    test('rejects if an envelope does not exist', () async {
      final envId = EnvelopeId('env-real');
      final missingId = EnvelopeId('env-fake');

      catalog.saveEnvelope(
        Envelope(
          id: envId,
          name: 'Real Envelope',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      final entries = [
        DistributionEntry(envelopeId: envId, amountUsd: 100),
        DistributionEntry(envelopeId: missingId, amountUsd: -100),
      ];

      await expectLater(
        () => recordDistribution(
          eventId: EventId('evt-2'),
          deviceId: 'dev-1',
          entries: entries,
        ),
        throwsA(isA<TargetNotFound>()),
      );

      expect(store.events.isEmpty, isTrue);
    });

    test(
      'generates EnvelopeTarget postings in USD and persists successfully',
      () async {
        final envId1 = EnvelopeId('env-1');
        final envId2 = EnvelopeId('env-2');
        final envId3 = EnvelopeId('env-3');

        for (var id in [envId1, envId2, envId3]) {
          catalog.saveEnvelope(
            Envelope(
              id: id,
              name: 'Envelope ${id.value}',
              role: EnvelopeRole.none,
              isArchived: false,
              updatedAt: DateTime.now(),
            ),
          );
        }

        final entries = [
          DistributionEntry(envelopeId: envId1, amountUsd: -150),
          DistributionEntry(envelopeId: envId2, amountUsd: 100),
          DistributionEntry(envelopeId: envId3, amountUsd: 50),
        ];

        await recordDistribution(
          eventId: EventId('evt-3'),
          deviceId: 'dev-1',
          entries: entries,
        );

        expect(store.events.length, equals(1));
        final tx = store.events.first;
        expect(tx.metadata.type, equals('Distribution'));

        expect(tx.postings.length, equals(3));

        // Verification of projections
        expect(projections.envelopeUsdBalance(envId1), equals(-150));
        expect(projections.envelopeUsdBalance(envId2), equals(100));
        expect(projections.envelopeUsdBalance(envId3), equals(50));

        // Native amount must equal USD amount, currency must be USD
        for (var posting in tx.postings) {
          expect(posting.target, isA<EnvelopeTarget>());
          expect(posting.currency, equals(CurrencyCode('USD')));
          expect(
            posting.amountNative.amount,
            equals(BigInt.from(posting.amountUsd)),
          );
        }
      },
    );
  });
}
