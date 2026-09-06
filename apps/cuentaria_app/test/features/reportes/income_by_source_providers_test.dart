import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:cuentaria_app/features/reportes/application/income_by_source_providers.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reportes/reportes.dart';
import 'package:shared_kernel/shared_kernel.dart';

void main() {
  group('incomeBySourceProvider', () {
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
      String type = 'Income',
      EventId? reverses,
      String? source,
      required String eventId,
    }) => TransactionMetadata(
      eventId: EventId(eventId),
      type: type,
      occurredAt: DomainTimestamp(occurredAt),
      recordedAt: DomainTimestamp(occurredAt),
      deviceId: 'dev-test',
      schemaVersion: 1,
      reverses: reverses,
      source: source,
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

    Future<EnvelopeId> stageEnvelopeId() async {
      final catalog = await container.read(catalogRepositoryProvider.future);
      return catalog.getSystemEnvelope(EnvelopeRole.stage);
    }

    test(
      'groups incomes by source, Acme first with two incomes summed',
      () async {
        final stage = await stageEnvelopeId();
        final occurredAt = DateTime.utc(2026, 8, 15);

        await append(
          Transaction.create(
            postings: [accountPosting(30000), envelopePosting(stage, 30000)],
            metadata: metaAt(
              occurredAt,
              eventId: 'evt-acme-300',
              source: 'Acme',
            ),
          ),
        );
        await append(
          Transaction.create(
            postings: [accountPosting(15000), envelopePosting(stage, 15000)],
            metadata: metaAt(occurredAt, eventId: 'evt-sin-fuente-150'),
          ),
        );
        await append(
          Transaction.create(
            postings: [accountPosting(20000), envelopePosting(stage, 20000)],
            metadata: metaAt(
              occurredAt,
              eventId: 'evt-acme-200',
              source: 'Acme',
            ),
          ),
        );

        final result = await container.read(
          incomeBySourceProvider(august).future,
        );

        expect(result.totalUsdCents, 65000);
        expect(result.rows.map((r) => r.label), ['Acme', 'Sin fuente']);
        expect(result.rows[0].amountUsdCents, 50000);
        expect(result.rows[1].amountUsdCents, 15000);
      },
    );

    test('an Opening balance never appears', () async {
      final catalog = await container.read(catalogRepositoryProvider.future);
      final openingId = catalog.getSystemEnvelope(EnvelopeRole.opening);

      await append(
        Transaction.create(
          postings: [
            accountPosting(100000),
            envelopePosting(openingId, 100000),
          ],
          metadata: metaAt(
            DateTime.utc(2026, 8, 15),
            type: 'Opening',
            eventId: 'evt-opening',
          ),
        ),
      );

      final result = await container.read(
        incomeBySourceProvider(august).future,
      );

      expect(result.isEmpty, isTrue);
    });

    test('an absorbed Adjustment never appears', () async {
      final catalog = await container.read(catalogRepositoryProvider.future);
      final adjustmentsId = catalog.getSystemEnvelope(EnvelopeRole.adjustments);

      await append(
        Transaction.create(
          postings: [accountPosting(60), envelopePosting(adjustmentsId, 60)],
          metadata: metaAt(
            DateTime.utc(2026, 8, 15),
            type: 'Adjustment',
            eventId: 'evt-adjustment',
          ),
        ),
      );

      final result = await container.read(
        incomeBySourceProvider(august).future,
      );

      expect(result.isEmpty, isTrue);
    });

    test(
      'compares against the previous full month: Acme \$400 in July, '
      '\$500 in August reads as +25%; a source only in July never appears',
      () async {
        final stage = await stageEnvelopeId();

        await append(
          Transaction.create(
            postings: [accountPosting(40000), envelopePosting(stage, 40000)],
            metadata: metaAt(
              DateTime.utc(2026, 7, 15),
              eventId: 'evt-july-acme',
              source: 'Acme',
            ),
          ),
        );
        await append(
          Transaction.create(
            postings: [accountPosting(10000), envelopePosting(stage, 10000)],
            metadata: metaAt(
              DateTime.utc(2026, 7, 15),
              eventId: 'evt-july-only',
              source: 'Solo julio',
            ),
          ),
        );
        await append(
          Transaction.create(
            postings: [accountPosting(50000), envelopePosting(stage, 50000)],
            metadata: metaAt(
              DateTime.utc(2026, 8, 15),
              eventId: 'evt-august-acme',
              source: 'Acme',
            ),
          ),
        );

        final result = await container.read(
          incomeBySourceProvider(august).future,
        );

        final row = result.rows.single;
        expect(row.label, 'Acme');
        expect(row.amountUsdCents, 50000);
        expect(row.previousAmountUsdCents, 40000);
        expect(row.changePercent, 25);
      },
    );

    test('invalidates itself when a transaction is recorded', () async {
      final initial = await container.read(
        incomeBySourceProvider(august).future,
      );
      expect(initial.isEmpty, isTrue);

      final stage = await stageEnvelopeId();
      final store = await container.read(eventStoreProvider.future);
      final eventBus = container.read(eventBusProvider);
      final tx = Transaction.create(
        postings: [accountPosting(30000), envelopePosting(stage, 30000)],
        metadata: metaAt(
          DateTime.utc(2026, 8, 15),
          eventId: 'evt-reactive',
          source: 'Acme',
        ),
      );
      await store.append(tx);
      eventBus.publish(tx);

      final updated = await container.read(
        incomeBySourceProvider(august).future,
      );
      expect(updated.rows.single.amountUsdCents, 30000);
    });
  });
}
