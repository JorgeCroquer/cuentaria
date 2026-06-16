import 'package:test/test.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/domain/ports/log_filters.dart';

void main() {
  group('InMemoryEventStore', () {
    test('append returns true on insert and false on duplicate', () async {
      final store = InMemoryEventStore();

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

      final tx = Transaction.create(postings: postings, metadata: metadata);

      expect(await store.append(tx), isTrue);
      expect(await store.append(tx), isFalse);
      expect(store.events.length, equals(1));
    });

    test('hasReversal returns true only after reversal is appended', () async {
      final store = InMemoryEventStore();

      final origId = EventId('evt-orig');
      final metadataOrig = TransactionMetadata(
        eventId: origId,
        type: 'Income',
        occurredAt: DomainTimestamp(DateTime.utc(2026, 6, 11)),
        recordedAt: DomainTimestamp(DateTime.utc(2026, 6, 11, 12)),
        deviceId: 'device-1',
        schemaVersion: 1,
      );

      final txOrig = Transaction.create(
        postings: [
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
        ],
        metadata: metadataOrig,
      );

      await store.append(txOrig);
      expect(await store.hasReversal(origId), isFalse);

      final metadataRev = TransactionMetadata(
        eventId: EventId('evt-rev'),
        type: 'Reversal',
        occurredAt: DomainTimestamp(DateTime.utc(2026, 6, 11)),
        recordedAt: DomainTimestamp(DateTime.utc(2026, 6, 11, 12)),
        deviceId: 'device-1',
        schemaVersion: 1,
        reverses: origId,
      );

      final txRev = Transaction.create(
        postings: [
          Posting(
            target: AccountTarget(AccountId('acc-1')),
            amountNative: Money(
              amount: BigInt.from(-100),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: -100,
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
        ],
        metadata: metadataRev,
      );

      await store.append(txRev);
      expect(await store.hasReversal(origId), isTrue);
    });

    test('queryLog filters by account, envelope and date range', () async {
      final store = InMemoryEventStore();

      Transaction createTx(
        String id,
        AccountId? accId,
        EnvelopeId? envId,
        DateTime occurred,
      ) {
        final postings = <Posting>[];
        if (accId != null) {
          postings.add(
            Posting(
              target: AccountTarget(accId),
              amountNative: Money(
                amount: BigInt.from(100),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: 100,
            ),
          );
        }
        if (envId != null) {
          postings.add(
            Posting(
              target: EnvelopeTarget(envId),
              amountNative: Money(
                amount: BigInt.from(100),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: accId != null ? 100 : 0,
            ),
          );
        }
        // ensure balance if both present
        return Transaction.create(
          metadata: TransactionMetadata(
            eventId: EventId(id),
            type: 'Test',
            occurredAt: DomainTimestamp(occurred),
            recordedAt: DomainTimestamp(DateTime.utc(2026, 6, 11, 12)),
            deviceId: 'device-1',
            schemaVersion: 1,
          ),
          postings: postings,
        );
      }

      final acc1 = AccountId('acc-1');
      final acc2 = AccountId('acc-2');
      final env1 = EnvelopeId('env-1');
      final env2 = EnvelopeId('env-2');

      final tx1 = createTx('evt-1', acc1, env1, DateTime.utc(2026, 6, 1));
      final tx2 = createTx('evt-2', acc2, env2, DateTime.utc(2026, 6, 5));
      final tx3 = createTx('evt-3', acc1, env2, DateTime.utc(2026, 6, 10));

      await store.append(tx1);
      await store.append(tx2);
      await store.append(tx3);

      final byAccount = await store.queryLog(
        filters: LogFilters(account: acc1),
      );
      expect(byAccount.map((t) => t.metadata.eventId.value).toSet(), {
        'evt-1',
        'evt-3',
      });

      final byEnvelope = await store.queryLog(
        filters: LogFilters(envelope: env2),
      );
      expect(byEnvelope.map((t) => t.metadata.eventId.value).toSet(), {
        'evt-2',
        'evt-3',
      });

      final byDate = await store.queryLog(
        filters: LogFilters(
          from: DomainTimestamp(DateTime.utc(2026, 6, 4)),
          to: DomainTimestamp(DateTime.utc(2026, 6, 6)),
        ),
      );
      expect(byDate.map((t) => t.metadata.eventId.value).toSet(), {'evt-2'});

      final combined = await store.queryLog(
        filters: LogFilters(account: acc1, envelope: env1),
      );
      expect(combined.map((t) => t.metadata.eventId.value).toSet(), {'evt-1'});
    });

    test('queryLog returns events with deterministic total ordering', () async {
      final store = InMemoryEventStore();

      Transaction createTx(String id, DateTime occurred, DateTime recorded) {
        return Transaction.create(
          metadata: TransactionMetadata(
            eventId: EventId(id),
            type: 'Test',
            occurredAt: DomainTimestamp(occurred),
            recordedAt: DomainTimestamp(recorded),
            deviceId: 'device-1',
            schemaVersion: 1,
          ),
          postings: [
            Posting(
              target: AccountTarget(AccountId('acc-1')),
              amountNative: Money(
                amount: BigInt.from(10),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: 10,
            ),
            Posting(
              target: EnvelopeTarget(EnvelopeId('env-1')),
              amountNative: Money(
                amount: BigInt.from(10),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: 10,
            ),
          ],
        );
      }

      // Different occurredAt, different recordedAt
      final txA = createTx(
        'evt-a',
        DateTime.utc(2026, 6, 3),
        DateTime.utc(2026, 6, 10),
      );
      final txB = createTx(
        'evt-b',
        DateTime.utc(2026, 6, 1),
        DateTime.utc(2026, 6, 11),
      );
      final txC = createTx(
        'evt-c',
        DateTime.utc(2026, 6, 3),
        DateTime.utc(2026, 6, 9),
      );

      // Insert in non-chronological order
      await store.append(txC);
      await store.append(txA);
      await store.append(txB);

      final results = await store.queryLog();

      // Deterministic order: by occurredAt first, then recordedAt, then eventId
      final ids = results.map((t) => t.metadata.eventId.value).toList();
      expect(ids, equals(['evt-b', 'evt-c', 'evt-a']));
    });
  });
}
