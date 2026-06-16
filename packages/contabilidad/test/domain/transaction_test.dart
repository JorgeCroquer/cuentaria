import 'package:test/test.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/domain/transaction_error.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:shared_kernel/shared_kernel.dart';

void main() {
  group('Transaction', () {
    test('create throws EmptyTransaction if postings is empty', () {
      final metadata = TransactionMetadata(
        eventId: EventId('evt-123'),
        type: 'Income',
        occurredAt: DomainTimestamp(DateTime.utc(2026, 6, 11)),
        recordedAt: DomainTimestamp(DateTime.utc(2026, 6, 11, 12)),
        deviceId: 'device-1',
        schemaVersion: 1,
      );

      expect(
        () => Transaction.create(postings: [], metadata: metadata),
        throwsA(isA<EmptyTransaction>()),
      );
    });

    test('create throws UnbalancedTransaction if USD amounts do not match', () {
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
            amount: BigInt.from(90),
            currency: CurrencyCode('USD'),
          ),
          currency: CurrencyCode('USD'),
          amountUsd: 90,
        ),
      ];

      expect(
        () => Transaction.create(postings: postings, metadata: metadata),
        throwsA(isA<UnbalancedTransaction>()),
      );
    });

    test('create accepts zero-sum of Account-only dimension (Transfer)', () {
      final metadata = TransactionMetadata(
        eventId: EventId('evt-123'),
        type: 'Transfer',
        occurredAt: DomainTimestamp(DateTime.utc(2026, 6, 11)),
        recordedAt: DomainTimestamp(DateTime.utc(2026, 6, 11, 12)),
        deviceId: 'device-1',
        schemaVersion: 1,
      );

      final postings = [
        Posting(
          target: AccountTarget(AccountId('acc-1')),
          amountNative: Money(
            amount: BigInt.from(-50),
            currency: CurrencyCode('USD'),
          ),
          currency: CurrencyCode('USD'),
          amountUsd: -50,
        ),
        Posting(
          target: AccountTarget(AccountId('acc-2')),
          amountNative: Money(
            amount: BigInt.from(50),
            currency: CurrencyCode('USD'),
          ),
          currency: CurrencyCode('USD'),
          amountUsd: 50,
        ),
      ];

      final tx = Transaction.create(postings: postings, metadata: metadata);
      expect(tx.postings, equals(postings));
    });

    test(
      'create accepts zero-sum of Envelope-only dimension (Distribution)',
      () {
        final metadata = TransactionMetadata(
          eventId: EventId('evt-124'),
          type: 'Distribution',
          occurredAt: DomainTimestamp(DateTime.utc(2026, 6, 11)),
          recordedAt: DomainTimestamp(DateTime.utc(2026, 6, 11, 12)),
          deviceId: 'device-1',
          schemaVersion: 1,
        );

        final postings = [
          Posting(
            target: EnvelopeTarget(EnvelopeId('env-1')),
            amountNative: Money(
              amount: BigInt.from(-30),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: -30,
          ),
          Posting(
            target: EnvelopeTarget(EnvelopeId('env-2')),
            amountNative: Money(
              amount: BigInt.from(30),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: 30,
          ),
        ];

        final tx = Transaction.create(postings: postings, metadata: metadata);
        expect(tx.postings, equals(postings));
      },
    );

    test('postings is immutable after create', () {
      final metadata = TransactionMetadata(
        eventId: EventId('evt-125'),
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

      expect(
        () => tx.postings.add(
          Posting(
            target: AccountTarget(AccountId('acc-2')),
            amountNative: Money(
              amount: BigInt.from(50),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: 50,
          ),
        ),
        throwsUnsupportedError,
      );
    });
  });
}
