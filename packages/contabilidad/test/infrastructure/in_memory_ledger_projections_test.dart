import 'package:test/test.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:contabilidad/domain/account_balance.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';

void main() {
  group('InMemoryLedgerProjections', () {
    test('apply increments balances correctly', () {
      final projections = InMemoryLedgerProjections();

      final accId = AccountId('acc-1');
      final envId = EnvelopeId('env-1');

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
          target: AccountTarget(accId),
          amountNative: Money(
            amount: BigInt.from(100),
            currency: CurrencyCode('USD'),
          ),
          currency: CurrencyCode('USD'),
          amountUsd: 100,
        ),
        Posting(
          target: EnvelopeTarget(envId),
          amountNative: Money(
            amount: BigInt.from(100),
            currency: CurrencyCode('USD'),
          ),
          currency: CurrencyCode('USD'),
          amountUsd: 100,
        ),
      ];

      final tx = Transaction.create(postings: postings, metadata: metadata);

      projections.apply(tx);

      final accountBal = projections.accountBalance(accId);
      expect(
        accountBal.native,
        equals(Money(amount: BigInt.from(100), currency: CurrencyCode('USD'))),
      );
      expect(accountBal.usd, equals(100));

      final envelopeBal = projections.envelopeUsdBalance(envId);
      expect(envelopeBal, equals(100));
    });

    test('apply accumulates multiple transactions', () {
      final projections = InMemoryLedgerProjections();
      final accId = AccountId('acc-1');
      final envId = EnvelopeId('env-1');

      for (var i = 1; i <= 3; i++) {
        final tx = Transaction.create(
          metadata: TransactionMetadata(
            eventId: EventId('evt-$i'),
            type: 'Income',
            occurredAt: DomainTimestamp(DateTime.utc(2026, 6, i)),
            recordedAt: DomainTimestamp(DateTime.utc(2026, 6, i, 12)),
            deviceId: 'device-1',
            schemaVersion: 1,
          ),
          postings: [
            Posting(
              target: AccountTarget(accId),
              amountNative: Money(
                amount: BigInt.from(50),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: 50,
            ),
            Posting(
              target: EnvelopeTarget(envId),
              amountNative: Money(
                amount: BigInt.from(50),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: 50,
            ),
          ],
        );
        projections.apply(tx);
      }

      expect(projections.accountBalance(accId).usd, equals(150));
      expect(projections.envelopeUsdBalance(envId), equals(150));
    });

    test('clear resets all balances to zero', () {
      final projections = InMemoryLedgerProjections();
      final accId = AccountId('acc-1');
      final envId = EnvelopeId('env-1');

      final tx = Transaction.create(
        metadata: TransactionMetadata(
          eventId: EventId('evt-1'),
          type: 'Income',
          occurredAt: DomainTimestamp(DateTime.utc(2026, 6, 1)),
          recordedAt: DomainTimestamp(DateTime.utc(2026, 6, 1, 12)),
          deviceId: 'device-1',
          schemaVersion: 1,
        ),
        postings: [
          Posting(
            target: AccountTarget(accId),
            amountNative: Money(
              amount: BigInt.from(200),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: 200,
          ),
          Posting(
            target: EnvelopeTarget(envId),
            amountNative: Money(
              amount: BigInt.from(200),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: 200,
          ),
        ],
      );

      projections.apply(tx);
      expect(projections.accountBalance(accId).usd, equals(200));
      expect(projections.envelopeUsdBalance(envId), equals(200));

      projections.clear();
      expect(projections.accountBalance(accId).usd, equals(0));
      expect(projections.envelopeUsdBalance(envId), equals(0));
    });

    test(
      'accountBalance returns zero-valued AccountBalance for unknown id',
      () {
        final projections = InMemoryLedgerProjections();
        final bal = projections.accountBalance(AccountId('unknown'));
        expect(bal, isA<AccountBalance>());
        expect(bal.usd, equals(0));
        expect(bal.native.amount, equals(BigInt.zero));
      },
    );

    test('envelopeUsdBalance returns 0 for unknown id', () {
      final projections = InMemoryLedgerProjections();
      expect(projections.envelopeUsdBalance(EnvelopeId('unknown')), equals(0));
    });
  });
}
