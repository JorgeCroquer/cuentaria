import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:cuentaria_app/features/reportes/application/spending_by_envelope_providers.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reportes/reportes.dart';
import 'package:shared_kernel/shared_kernel.dart';

void main() {
  group('spendingByEnvelopeProvider', () {
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
      String type = 'Expense',
      EventId? reverses,
      required String eventId,
    }) => TransactionMetadata(
      eventId: EventId(eventId),
      type: type,
      occurredAt: DomainTimestamp(occurredAt),
      recordedAt: DomainTimestamp(occurredAt),
      deviceId: 'dev-test',
      schemaVersion: 1,
      reverses: reverses,
    );

    Posting accountPosting(int amountUsd) => Posting(
      target: AccountTarget(AccountId('acc-1')),
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

    test(
      'sums expenses into their envelope and totals only user envelopes',
      () async {
        final catalog = await container.read(catalogRepositoryProvider.future);
        final comida = EnvelopeId('comida');
        await catalog.saveEnvelope(
          Envelope(
            id: comida,
            name: 'Comida',
            role: EnvelopeRole.none,
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );
        final transporte = EnvelopeId('transporte');
        await catalog.saveEnvelope(
          Envelope(
            id: transporte,
            name: 'Transporte',
            role: EnvelopeRole.none,
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        final occurredAt = DateTime.utc(2026, 8, 15);
        await append(
          Transaction.create(
            postings: [accountPosting(-4000), envelopePosting(comida, -4000)],
            metadata: metaAt(occurredAt, eventId: 'evt-comida-40'),
          ),
        );
        await append(
          Transaction.create(
            postings: [
              accountPosting(-2500),
              envelopePosting(transporte, -2500),
            ],
            metadata: metaAt(occurredAt, eventId: 'evt-transporte-25'),
          ),
        );

        final result = await container.read(
          spendingByEnvelopeProvider(august).future,
        );

        expect(result.totalUsdCents, 6500);
        expect(result.rows.map((r) => r.label), ['Comida', 'Transporte']);
        expect(result.rows[0].amountUsdCents, 4000);
        expect(result.rows[1].amountUsdCents, 2500);
      },
    );

    test('a Transfer between accounts never appears', () async {
      final occurredAt = DateTime.utc(2026, 8, 15);
      await append(
        Transaction.create(
          postings: [
            accountPosting(-50000),
            Posting(
              target: AccountTarget(AccountId('acc-2')),
              amountNative: Money(amount: BigInt.from(50000), currency: usd),
              currency: usd,
              amountUsd: 50000,
            ),
          ],
          metadata: metaAt(
            occurredAt,
            type: 'Transfer',
            eventId: 'evt-transfer',
          ),
        ),
      );

      final result = await container.read(
        spendingByEnvelopeProvider(august).future,
      );

      expect(result.isEmpty, isTrue);
    });

    test('a Distribution between two user envelopes never appears', () async {
      final catalog = await container.read(catalogRepositoryProvider.future);
      final comida = EnvelopeId('comida');
      await catalog.saveEnvelope(
        Envelope(
          id: comida,
          name: 'Comida',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );
      final transporte = EnvelopeId('transporte');
      await catalog.saveEnvelope(
        Envelope(
          id: transporte,
          name: 'Transporte',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      final occurredAt = DateTime.utc(2026, 8, 15);
      await append(
        Transaction.create(
          postings: [
            envelopePosting(comida, -5000),
            envelopePosting(transporte, 5000),
          ],
          metadata: metaAt(
            occurredAt,
            type: 'Distribution',
            eventId: 'evt-distribution',
          ),
        ),
      );

      final result = await container.read(
        spendingByEnvelopeProvider(august).future,
      );

      expect(result.isEmpty, isTrue);
    });

    test('an Adjustment of -\$0.60 appears as its own Ajustes row, envelopes '
        'unaffected', () async {
      final catalog = await container.read(catalogRepositoryProvider.future);
      final ajustesId = catalog.getSystemEnvelope(EnvelopeRole.adjustments);

      final occurredAt = DateTime.utc(2026, 8, 15);
      await append(
        Transaction.create(
          postings: [accountPosting(-60), envelopePosting(ajustesId, -60)],
          metadata: metaAt(
            occurredAt,
            type: 'Adjustment',
            eventId: 'evt-adjustment',
          ),
        ),
      );

      final result = await container.read(
        spendingByEnvelopeProvider(august).future,
      );

      expect(result.adjustments?.label, 'Ajustes');
      expect(result.adjustments?.amountUsdCents, -60);
      expect(result.rows, isEmpty);
      // The system row must not inflate the user-envelope total.
      expect(result.totalUsdCents, 0);
    });

    test(
      'a CryptoSale differential of +\$12 appears in Diferencial realizado',
      () async {
        final catalog = await container.read(catalogRepositoryProvider.future);
        final diferencialId = catalog.getSystemEnvelope(
          EnvelopeRole.differential,
        );

        final occurredAt = DateTime.utc(2026, 8, 15);
        await append(
          Transaction.create(
            postings: [
              accountPosting(-8800),
              Posting(
                target: AccountTarget(AccountId('acc-2')),
                amountNative: Money(amount: BigInt.from(10000), currency: usd),
                currency: usd,
                amountUsd: 10000,
              ),
              envelopePosting(diferencialId, 1200),
            ],
            metadata: metaAt(
              occurredAt,
              type: 'CryptoSale',
              eventId: 'evt-crypto',
            ),
          ),
        );

        final result = await container.read(
          spendingByEnvelopeProvider(august).future,
        );

        expect(result.differential?.label, 'Diferencial realizado');
        expect(result.differential?.amountUsdCents, 1200);
      },
    );

    test('a Reversal of a \$40 expense recorded in a later month leaves this '
        'month at \$0 and does not appear', () async {
      final catalog = await container.read(catalogRepositoryProvider.future);
      final comida = EnvelopeId('comida');
      await catalog.saveEnvelope(
        Envelope(
          id: comida,
          name: 'Comida',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      await append(
        Transaction.create(
          postings: [accountPosting(-4000), envelopePosting(comida, -4000)],
          metadata: metaAt(
            DateTime.utc(2026, 8, 15),
            eventId: 'evt-expense-40',
          ),
        ),
      );
      await append(
        Transaction.create(
          postings: [accountPosting(4000), envelopePosting(comida, 4000)],
          metadata: metaAt(
            DateTime.utc(2026, 9, 5),
            type: 'Reversal',
            reverses: EventId('evt-expense-40'),
            eventId: 'evt-reversal',
          ),
        ),
      );

      final result = await container.read(
        spendingByEnvelopeProvider(august).future,
      );
      expect(result.isEmpty, isTrue);

      final september = await container.read(
        spendingByEnvelopeProvider(ReportMonth(2026, 9)).future,
      );
      expect(september.isEmpty, isTrue);
    });

    test('compares against the previous full month: July \$100, August \$130 '
        'reads as +30%', () async {
      final catalog = await container.read(catalogRepositoryProvider.future);
      final comida = EnvelopeId('comida');
      await catalog.saveEnvelope(
        Envelope(
          id: comida,
          name: 'Comida',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      await append(
        Transaction.create(
          postings: [accountPosting(-10000), envelopePosting(comida, -10000)],
          metadata: metaAt(DateTime.utc(2026, 7, 15), eventId: 'evt-july'),
        ),
      );
      await append(
        Transaction.create(
          postings: [accountPosting(-13000), envelopePosting(comida, -13000)],
          metadata: metaAt(DateTime.utc(2026, 8, 15), eventId: 'evt-august'),
        ),
      );

      final result = await container.read(
        spendingByEnvelopeProvider(august).future,
      );

      final row = result.rows.single;
      expect(row.amountUsdCents, 13000);
      expect(row.previousAmountUsdCents, 10000);
      expect(row.changePercent, 30);
    });

    test('invalidates itself when a transaction is recorded', () async {
      final initial = await container.read(
        spendingByEnvelopeProvider(august).future,
      );
      expect(initial.isEmpty, isTrue);

      final catalog = await container.read(catalogRepositoryProvider.future);
      final comida = EnvelopeId('comida');
      await catalog.saveEnvelope(
        Envelope(
          id: comida,
          name: 'Comida',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      final store = await container.read(eventStoreProvider.future);
      final eventBus = container.read(eventBusProvider);
      final tx = Transaction.create(
        postings: [accountPosting(-4000), envelopePosting(comida, -4000)],
        metadata: metaAt(DateTime.utc(2026, 8, 15), eventId: 'evt-reactive'),
      );
      await store.append(tx);
      eventBus.publish(tx);

      final updated = await container.read(
        spendingByEnvelopeProvider(august).future,
      );
      expect(updated.rows.single.amountUsdCents, 4000);
    });
  });
}
