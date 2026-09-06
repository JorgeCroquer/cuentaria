import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:cuentaria_app/features/reportes/application/exchange_differential_providers.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reportes/reportes.dart';
import 'package:shared_kernel/shared_kernel.dart';

void main() {
  group('exchangeDifferentialProvider', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
    });

    tearDown(() => container.dispose());

    final august = ReportMonth(2026, 8);
    final usd = CurrencyCode('USD');

    Future<void> append(Transaction tx) async {
      final store = await container.read(eventStoreProvider.future);
      await store.append(tx);
    }

    TransactionMetadata metaAt(
      DateTime occurredAt, {
      String type = 'CryptoSale',
      required String eventId,
    }) => TransactionMetadata(
      eventId: EventId(eventId),
      type: type,
      occurredAt: DomainTimestamp(occurredAt),
      recordedAt: DomainTimestamp(occurredAt),
      deviceId: 'dev-test',
      schemaVersion: 1,
    );

    Posting accountPosting(String accountId, int amountUsd) => Posting(
      target: AccountTarget(AccountId(accountId)),
      amountNative: Money(amount: BigInt.from(amountUsd), currency: usd),
      currency: usd,
      amountUsd: amountUsd,
    );

    Posting envelopePosting(EnvelopeId envelopeId, int amountUsd) => Posting(
      target: EnvelopeTarget(envelopeId),
      amountNative: Money(amount: BigInt.from(amountUsd), currency: usd),
      currency: usd,
      amountUsd: amountUsd,
    );

    test('returns 12 months ending at the requested month', () async {
      final result = await container.read(
        exchangeDifferentialProvider(august).future,
      );

      expect(result, hasLength(12));
      expect(result.last.month, august);
    });

    test('a crypto sale realizing +\$12 in August sums into that month\'s '
        'realizado', () async {
      final catalog = await container.read(catalogRepositoryProvider.future);
      final diferencialId = catalog.getSystemEnvelope(
        EnvelopeRole.differential,
      );

      await append(
        Transaction.create(
          postings: [
            accountPosting('acc-1', -8800),
            accountPosting('acc-2', 10000),
            envelopePosting(diferencialId, 1200),
          ],
          metadata: metaAt(DateTime.utc(2026, 8, 15), eventId: 'evt-crypto'),
        ),
      );

      final result = await container.read(
        exchangeDifferentialProvider(august).future,
      );

      expect(result.last.realizadoUsdCents, 1200);
    });

    test(
      'an account funded in USD with no foreign currency leaves no realizado '
      'at \$0, never blank',
      () async {
        final catalog = await container.read(catalogRepositoryProvider.future);
        await catalog.saveAccount(
          Account(
            id: AccountId('acc-1'),
            name: 'Test',
            nativeCurrency: usd,
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );
        await append(
          Transaction.create(
            postings: [
              accountPosting('acc-1', 5000),
              envelopePosting(EnvelopeId('sys-stage'), 5000),
            ],
            metadata: metaAt(
              DateTime.utc(2026, 8, 15),
              type: 'Adjustment',
              eventId: 'evt-fund',
            ),
          ),
        );

        final result = await container.read(
          exchangeDifferentialProvider(august).future,
        );

        expect(result.last.noRealizadoUsdCents, 0);
      },
    );

    test('a foreign currency with no rate observation leaves no realizado '
        'blank', () async {
      final ves = CurrencyCode('VES');
      final catalog = await container.read(catalogRepositoryProvider.future);
      await catalog.saveAccount(
        Account(
          id: AccountId('acc-ves'),
          name: 'Test VES',
          nativeCurrency: ves,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );
      await append(
        Transaction.create(
          postings: [
            Posting(
              target: AccountTarget(AccountId('acc-ves')),
              amountNative: Money(amount: BigInt.from(750000), currency: ves),
              currency: ves,
              amountUsd: 10000,
            ),
            Posting(
              target: EnvelopeTarget(EnvelopeId('sys-stage')),
              amountNative: Money(amount: BigInt.from(750000), currency: ves),
              currency: ves,
              amountUsd: 10000,
            ),
          ],
          metadata: metaAt(
            DateTime.utc(2026, 8, 1),
            type: 'Adjustment',
            eventId: 'evt-fund-ves',
          ),
        ),
      );

      final result = await container.read(
        exchangeDifferentialProvider(august).future,
      );

      expect(result.last.noRealizadoUsdCents, isNull);
    });

    test('invalidates itself when a transaction is recorded', () async {
      final initial = await container.read(
        exchangeDifferentialProvider(august).future,
      );
      expect(initial.last.realizadoUsdCents, 0);

      final catalog = await container.read(catalogRepositoryProvider.future);
      final diferencialId = catalog.getSystemEnvelope(
        EnvelopeRole.differential,
      );

      final store = await container.read(eventStoreProvider.future);
      final eventBus = container.read(eventBusProvider);
      final tx = Transaction.create(
        postings: [
          accountPosting('acc-1', -8800),
          accountPosting('acc-2', 10000),
          envelopePosting(diferencialId, 1200),
        ],
        metadata: metaAt(DateTime.utc(2026, 8, 15), eventId: 'evt-reactive'),
      );
      await store.append(tx);
      eventBus.publish(tx);

      final updated = await container.read(
        exchangeDifferentialProvider(august).future,
      );
      expect(updated.last.realizadoUsdCents, 1200);
    });
  });
}
