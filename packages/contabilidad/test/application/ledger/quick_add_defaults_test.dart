import 'package:test/test.dart';
import 'package:shared_kernel/shared_kernel.dart';

import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/application/ledger/quick_add_defaults.dart';

void main() {
  group('QuickAddDefaults', () {
    late InMemoryEventStore store;
    late QuickAddDefaults defaults;

    setUp(() {
      store = InMemoryEventStore();
      defaults = QuickAddDefaults(store);
    });

    Future<void> appendExpense({
      required String eventId,
      required String accountId,
      required String envelopeId,
      required DateTime occurredAt,
      String type = 'Expense',
    }) async {
      await store.append(
        Transaction.create(
          metadata: TransactionMetadata(
            eventId: EventId(eventId),
            type: type,
            occurredAt: DomainTimestamp(occurredAt),
            recordedAt: DomainTimestamp(occurredAt),
            deviceId: 'dev',
            schemaVersion: 1,
          ),
          postings: [
            Posting(
              target: AccountTarget(AccountId(accountId)),
              amountNative: Money(
                amount: BigInt.from(-100),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: -100,
            ),
            Posting(
              target: EnvelopeTarget(EnvelopeId(envelopeId)),
              amountNative: Money(
                amount: BigInt.from(-100),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: -100,
            ),
          ],
        ),
      );
    }

    test('lastUsedAccount returns null for an empty ledger', () async {
      expect(await defaults.lastUsedAccount(), isNull);
    });

    test(
      'lastUsedAccount returns the account of the most recent expense',
      () async {
        await appendExpense(
          eventId: 'evt-1',
          accountId: 'acc-old',
          envelopeId: 'env-1',
          occurredAt: DateTime.utc(2026, 1, 1),
        );
        await appendExpense(
          eventId: 'evt-2',
          accountId: 'acc-new',
          envelopeId: 'env-1',
          occurredAt: DateTime.utc(2026, 1, 2),
        );

        expect(await defaults.lastUsedAccount(), AccountId('acc-new'));
      },
    );

    test('lastUsedAccount ignores non-expense transactions', () async {
      await appendExpense(
        eventId: 'evt-1',
        accountId: 'acc-expense',
        envelopeId: 'env-1',
        occurredAt: DateTime.utc(2026, 1, 1),
      );
      await appendExpense(
        eventId: 'evt-2',
        accountId: 'acc-opening',
        envelopeId: 'env-1',
        occurredAt: DateTime.utc(2026, 1, 2),
        type: 'Opening',
      );

      expect(await defaults.lastUsedAccount(), AccountId('acc-expense'));
    });

    test('envelopesByFrequency returns empty for an empty ledger', () async {
      expect(await defaults.envelopesByFrequency(), isEmpty);
    });

    test(
      'envelopesByFrequency orders envelopes by descending expense count',
      () async {
        await appendExpense(
          eventId: 'evt-1',
          accountId: 'acc-1',
          envelopeId: 'env-rare',
          occurredAt: DateTime.utc(2026, 1, 1),
        );
        await appendExpense(
          eventId: 'evt-2',
          accountId: 'acc-1',
          envelopeId: 'env-frequent',
          occurredAt: DateTime.utc(2026, 1, 2),
        );
        await appendExpense(
          eventId: 'evt-3',
          accountId: 'acc-1',
          envelopeId: 'env-frequent',
          occurredAt: DateTime.utc(2026, 1, 3),
        );

        expect(await defaults.envelopesByFrequency(), [
          EnvelopeId('env-frequent'),
          EnvelopeId('env-rare'),
        ]);
      },
    );

    Future<void> appendIncome({
      required String eventId,
      required String accountId,
      required DateTime occurredAt,
      String? source,
    }) async {
      await store.append(
        Transaction.create(
          metadata: TransactionMetadata(
            eventId: EventId(eventId),
            type: 'Income',
            occurredAt: DomainTimestamp(occurredAt),
            recordedAt: DomainTimestamp(occurredAt),
            deviceId: 'dev',
            schemaVersion: 1,
            source: source,
          ),
          postings: [
            Posting(
              target: AccountTarget(AccountId(accountId)),
              amountNative: Money(
                amount: BigInt.from(100),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: 100,
            ),
            Posting(
              target: EnvelopeTarget(EnvelopeId('stage')),
              amountNative: Money(
                amount: BigInt.from(100),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: 100,
            ),
          ],
        ),
      );
    }

    test('previousIncomeSources returns empty for an empty ledger', () async {
      expect(await defaults.previousIncomeSources(), isEmpty);
    });

    test('previousIncomeSources dedupes and orders by recency', () async {
      await appendIncome(
        eventId: 'evt-1',
        accountId: 'acc-1',
        occurredAt: DateTime.utc(2026, 1, 1),
        source: 'Cliente A',
      );
      await appendIncome(
        eventId: 'evt-2',
        accountId: 'acc-1',
        occurredAt: DateTime.utc(2026, 1, 2),
        source: 'Cliente B',
      );
      await appendIncome(
        eventId: 'evt-3',
        accountId: 'acc-1',
        occurredAt: DateTime.utc(2026, 1, 3),
        source: 'Cliente A',
      );

      expect(await defaults.previousIncomeSources(), [
        'Cliente A',
        'Cliente B',
      ]);
    });

    test('previousIncomeSources ignores null/empty sources', () async {
      await appendIncome(
        eventId: 'evt-1',
        accountId: 'acc-1',
        occurredAt: DateTime.utc(2026, 1, 1),
        source: null,
      );

      expect(await defaults.previousIncomeSources(), isEmpty);
    });

    Future<void> appendMover({
      required String eventId,
      required String type,
      required String sourceAccountId,
      required String destinationAccountId,
      required DateTime occurredAt,
    }) async {
      await store.append(
        Transaction.create(
          metadata: TransactionMetadata(
            eventId: EventId(eventId),
            type: type,
            occurredAt: DomainTimestamp(occurredAt),
            recordedAt: DomainTimestamp(occurredAt),
            deviceId: 'dev',
            schemaVersion: 1,
          ),
          postings: [
            Posting(
              target: AccountTarget(AccountId(sourceAccountId)),
              amountNative: Money(
                amount: BigInt.from(-100),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: -100,
            ),
            Posting(
              target: AccountTarget(AccountId(destinationAccountId)),
              amountNative: Money(
                amount: BigInt.from(100),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: 100,
            ),
          ],
        ),
      );
    }

    test('lastUsedMoverPair returns null for an empty ledger', () async {
      expect(await defaults.lastUsedMoverPair(), isNull);
    });

    test('lastUsedMoverPair returns the accounts of the most recent Transfer '
        'or AcquisitionConversion', () async {
      await appendMover(
        eventId: 'evt-1',
        type: 'Transfer',
        sourceAccountId: 'acc-old-src',
        destinationAccountId: 'acc-old-dst',
        occurredAt: DateTime.utc(2026, 1, 1),
      );
      await appendMover(
        eventId: 'evt-2',
        type: 'AcquisitionConversion',
        sourceAccountId: 'acc-new-src',
        destinationAccountId: 'acc-new-dst',
        occurredAt: DateTime.utc(2026, 1, 2),
      );

      final pair = await defaults.lastUsedMoverPair();
      expect(pair!.sourceAccountId, AccountId('acc-new-src'));
      expect(pair.destinationAccountId, AccountId('acc-new-dst'));
    });

    test('lastUsedMoverPair ignores non-mover transactions', () async {
      await appendMover(
        eventId: 'evt-1',
        type: 'Transfer',
        sourceAccountId: 'acc-src',
        destinationAccountId: 'acc-dst',
        occurredAt: DateTime.utc(2026, 1, 1),
      );
      await appendExpense(
        eventId: 'evt-2',
        accountId: 'acc-expense',
        envelopeId: 'env-1',
        occurredAt: DateTime.utc(2026, 1, 2),
      );

      final pair = await defaults.lastUsedMoverPair();
      expect(pair!.sourceAccountId, AccountId('acc-src'));
      expect(pair.destinationAccountId, AccountId('acc-dst'));
    });
  });
}
