import 'package:test/test.dart';
import 'package:event_bus/event_bus.dart';
import 'package:shared_kernel/shared_kernel.dart';

import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:contabilidad/domain/transaction_error.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/catalog/exceptions.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';

void main() {
  group('RecordTransaction', () {
    test(
      'record with postings and metadata saves, projects and publishes',
      () async {
        final store = InMemoryEventStore();
        final projections = InMemoryLedgerProjections();
        final eventBus = SyncEventBus();

        final catalog = InMemoryCatalogRepository();
        catalog.saveAccount(
          Account(
            id: AccountId('acc-1'),
            name: 'Acc 1',
            nativeCurrency: CurrencyCode('USD'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );
        catalog.saveEnvelope(
          Envelope(
            id: EnvelopeId('env-1'),
            name: 'Env 1',
            role: EnvelopeRole.none,
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        final validator = ReferentialIntegrityValidator(catalog);

        final record = RecordTransaction(
          store: store,
          projections: projections,
          eventBus: eventBus,
          validator: validator,
        );

        final metadata = TransactionMetadata(
          eventId: EventId('evt-123'),
          type: 'Income',
          occurredAt: DomainTimestamp(DateTime.utc(2026, 6, 11)),
          recordedAt: DomainTimestamp(DateTime.utc(2026, 6, 11, 12)),
          deviceId: 'device-1',
          schemaVersion: 1,
        );

        final postings = [
          Posting(
            target: AccountTarget(AccountId('acc-1')),
            amountNative: Money(
              amount: BigInt.from(100),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: 100,
          ),
          Posting(
            target: EnvelopeTarget(EnvelopeId('env-1')),
            amountNative: Money(
              amount: BigInt.from(100),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: 100,
          ),
        ];

        final emittedEvents = <DomainEvent>[];
        eventBus.stream
            .where((e) => e is Transaction)
            .cast<Transaction>()
            .listen(emittedEvents.add);

        await record(postings: postings, metadata: metadata);

        expect(store.events.length, equals(1));
        expect(
          projections.envelopeUsdBalance(EnvelopeId('env-1')),
          equals(100),
        );
        expect(emittedEvents.length, equals(1));

        // Dedup: same event_id again
        await record(postings: postings, metadata: metadata);

        expect(store.events.length, equals(1));
        expect(
          projections.envelopeUsdBalance(EnvelopeId('env-1')),
          equals(100),
        );
        expect(emittedEvents.length, equals(1));
      },
    );

    test('record rejects unbalanced transaction', () async {
      final store = InMemoryEventStore();
      final projections = InMemoryLedgerProjections();
      final eventBus = SyncEventBus();

      final catalog = InMemoryCatalogRepository();
      catalog.saveAccount(
        Account(
          id: AccountId('acc-1'),
          name: 'Acc 1',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );
      catalog.saveEnvelope(
        Envelope(
          id: EnvelopeId('env-1'),
          name: 'Env 1',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      final validator = ReferentialIntegrityValidator(catalog);

      final record = RecordTransaction(
        store: store,
        projections: projections,
        eventBus: eventBus,
        validator: validator,
      );

      final metadata = TransactionMetadata(
        eventId: EventId('evt-400'),
        type: 'Income',
        occurredAt: DomainTimestamp(DateTime.utc(2026, 6, 11)),
        recordedAt: DomainTimestamp(DateTime.utc(2026, 6, 11, 12)),
        deviceId: 'device-1',
        schemaVersion: 1,
      );

      final postings = [
        Posting(
          target: AccountTarget(AccountId('acc-1')),
          amountNative: Money(
            amount: BigInt.from(100),
            currency: CurrencyCode('USD'),
          ),
          currency: CurrencyCode('USD'),
          amountUsd: 100,
        ),
        Posting(
          target: EnvelopeTarget(EnvelopeId('env-1')),
          amountNative: Money(
            amount: BigInt.from(50),
            currency: CurrencyCode('USD'),
          ),
          currency: CurrencyCode('USD'),
          amountUsd: 50,
        ),
      ];

      expect(
        () => record(postings: postings, metadata: metadata),
        throwsA(isA<UnbalancedTransaction>()),
      );
    });

    test(
      'record rejects transaction if referential integrity fails without saving anything',
      () async {
        final store = InMemoryEventStore();
        final projections = InMemoryLedgerProjections();
        final eventBus = SyncEventBus();

        // Empty catalog!
        final catalog = InMemoryCatalogRepository();
        final validator = ReferentialIntegrityValidator(catalog);

        final record = RecordTransaction(
          store: store,
          projections: projections,
          eventBus: eventBus,
          validator: validator,
        );

        final metadata = TransactionMetadata(
          eventId: EventId('evt-500'),
          type: 'Income',
          occurredAt: DomainTimestamp(DateTime.utc(2026, 6, 11)),
          recordedAt: DomainTimestamp(DateTime.utc(2026, 6, 11, 12)),
          deviceId: 'device-1',
          schemaVersion: 1,
        );

        final postings = [
          Posting(
            target: AccountTarget(AccountId('acc-1')),
            amountNative: Money(
              amount: BigInt.from(100),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: 100,
          ),
          Posting(
            target: EnvelopeTarget(EnvelopeId('env-1')),
            amountNative: Money(
              amount: BigInt.from(-100),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: -100,
          ),
        ];

        await expectLater(
          () => record(postings: postings, metadata: metadata),
          throwsA(isA<TargetNotFound>()),
        );

        // Verify no events were saved
        expect(store.events.isEmpty, isTrue);
      },
    );
  });
}
