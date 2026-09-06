import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/catalog/models/funding_target.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:cuentaria_app/features/reportes/application/funding_pace_providers.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reportes/reportes.dart';
import 'package:shared_kernel/shared_kernel.dart';

void main() {
  group('fundingPaceProvider', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
    });

    tearDown(() => container.dispose());

    final august = ReportMonth(2026, 8);
    final usd = CurrencyCode('USD');
    final viaje = EnvelopeId('viaje');
    final stage = EnvelopeId('stage-1');

    Future<void> append(Transaction tx) async {
      final store = await container.read(eventStoreProvider.future);
      await store.append(tx);
      container.read(ledgerProjectionsProvider).apply(tx);
    }

    Posting envelopePosting(EnvelopeId envelopeId, int amountUsd) => Posting(
      target: EnvelopeTarget(envelopeId),
      amountNative: Money(amount: BigInt.from(amountUsd), currency: usd),
      currency: usd,
      amountUsd: amountUsd,
    );

    Future<void> saveViaje(FundingTarget target) async {
      final catalog = await container.read(catalogRepositoryProvider.future);
      await catalog.saveEnvelope(
        Envelope(
          id: viaje,
          name: 'Viaje',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        ).withTarget(target),
      );
    }

    test('a goal envelope funded ahead of its monthly requirement is on pace, '
        'required computed off the live post-aporte balance', () async {
      await saveViaje(
        GoalLine(amountUsd: 120000, dueDate: DateTime.utc(2027, 2, 1)),
      );

      await append(
        Transaction.create(
          postings: [
            envelopePosting(stage, -25000),
            envelopePosting(viaje, 25000),
          ],
          metadata: TransactionMetadata(
            eventId: EventId('evt-distribution'),
            type: 'Distribution',
            occurredAt: DomainTimestamp(DateTime.utc(2026, 8, 15)),
            recordedAt: DomainTimestamp(DateTime.utc(2026, 8, 15)),
            deviceId: 'dev-test',
            schemaVersion: 1,
          ),
        ),
      );

      final result = await container.read(fundingPaceProvider(august).future);

      final row = result.rows.single.row;
      expect(row.name, 'Viaje');
      expect(row.contributedThisMonthUsdCents, 25000);
      // (120000 - 25000 balance) / 6 months, rounded up.
      expect(row.requiredPerMonthUsdCents, 15834);
      expect(row.status, FundingPaceStatus.onPace);
    });

    test('an expense out of the envelope reduces its balance but not the '
        'aportado', () async {
      await saveViaje(
        GoalLine(amountUsd: 120000, dueDate: DateTime.utc(2027, 2, 1)),
      );

      await append(
        Transaction.create(
          postings: [
            envelopePosting(stage, -25000),
            envelopePosting(viaje, 25000),
          ],
          metadata: TransactionMetadata(
            eventId: EventId('evt-distribution'),
            type: 'Distribution',
            occurredAt: DomainTimestamp(DateTime.utc(2026, 8, 15)),
            recordedAt: DomainTimestamp(DateTime.utc(2026, 8, 15)),
            deviceId: 'dev-test',
            schemaVersion: 1,
          ),
        ),
      );
      await append(
        Transaction.create(
          postings: [
            Posting(
              target: AccountTarget(AccountId('acc-1')),
              amountNative: Money(amount: BigInt.from(-5000), currency: usd),
              currency: usd,
              amountUsd: -5000,
            ),
            envelopePosting(viaje, -5000),
          ],
          metadata: TransactionMetadata(
            eventId: EventId('evt-expense'),
            type: 'Expense',
            occurredAt: DomainTimestamp(DateTime.utc(2026, 8, 20)),
            recordedAt: DomainTimestamp(DateTime.utc(2026, 8, 20)),
            deviceId: 'dev-test',
            schemaVersion: 1,
          ),
        ),
      );

      final result = await container.read(fundingPaceProvider(august).future);

      final row = result.rows.single.row;
      expect(row.contributedThisMonthUsdCents, 25000);
    });

    test('a balance already at the goal is goalReached', () async {
      await saveViaje(
        GoalLine(amountUsd: 120000, dueDate: DateTime.utc(2027, 2, 1)),
      );

      await append(
        Transaction.create(
          postings: [
            envelopePosting(stage, -120000),
            envelopePosting(viaje, 120000),
          ],
          metadata: TransactionMetadata(
            eventId: EventId('evt-full'),
            type: 'Distribution',
            occurredAt: DomainTimestamp(DateTime.utc(2026, 7, 1)),
            recordedAt: DomainTimestamp(DateTime.utc(2026, 7, 1)),
            deviceId: 'dev-test',
            schemaVersion: 1,
          ),
        ),
      );

      final result = await container.read(fundingPaceProvider(august).future);

      expect(result.rows.single.row.status, FundingPaceStatus.goalReached);
    });

    test('an envelope with no funding target never appears', () async {
      final catalog = await container.read(catalogRepositoryProvider.future);
      await catalog.saveEnvelope(
        Envelope(
          id: viaje,
          name: 'Viaje',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      final result = await container.read(fundingPaceProvider(august).future);

      expect(result.isEmpty, isTrue);
    });

    test('no envelopes with a funding target means an empty result', () async {
      final result = await container.read(fundingPaceProvider(august).future);

      expect(result.isEmpty, isTrue);
    });

    test(
      'reports the last 12 months of aportes, oldest first, for the chart',
      () async {
        await saveViaje(
          GoalLine(amountUsd: 120000, dueDate: DateTime.utc(2027, 2, 1)),
        );

        await append(
          Transaction.create(
            postings: [
              envelopePosting(stage, -10000),
              envelopePosting(viaje, 10000),
            ],
            metadata: TransactionMetadata(
              eventId: EventId('evt-july'),
              type: 'Distribution',
              occurredAt: DomainTimestamp(DateTime.utc(2026, 7, 15)),
              recordedAt: DomainTimestamp(DateTime.utc(2026, 7, 15)),
              deviceId: 'dev-test',
              schemaVersion: 1,
            ),
          ),
        );
        await append(
          Transaction.create(
            postings: [
              envelopePosting(stage, -25000),
              envelopePosting(viaje, 25000),
            ],
            metadata: TransactionMetadata(
              eventId: EventId('evt-august'),
              type: 'Distribution',
              occurredAt: DomainTimestamp(DateTime.utc(2026, 8, 15)),
              recordedAt: DomainTimestamp(DateTime.utc(2026, 8, 15)),
              deviceId: 'dev-test',
              schemaVersion: 1,
            ),
          ),
        );

        final result = await container.read(fundingPaceProvider(august).future);

        final history = result.rows.single.monthlyContributionsUsdCents;
        expect(history, hasLength(12));
        expect(history.last, 25000);
        expect(history[history.length - 2], 10000);
      },
    );

    test('invalidates itself when a transaction is recorded', () async {
      await saveViaje(
        GoalLine(amountUsd: 120000, dueDate: DateTime.utc(2027, 2, 1)),
      );

      final initial = await container.read(fundingPaceProvider(august).future);
      expect(initial.rows.single.row.contributedThisMonthUsdCents, 0);

      final store = await container.read(eventStoreProvider.future);
      final projections = container.read(ledgerProjectionsProvider);
      final eventBus = container.read(eventBusProvider);
      final tx = Transaction.create(
        postings: [
          envelopePosting(stage, -25000),
          envelopePosting(viaje, 25000),
        ],
        metadata: TransactionMetadata(
          eventId: EventId('evt-reactive'),
          type: 'Distribution',
          occurredAt: DomainTimestamp(DateTime.utc(2026, 8, 15)),
          recordedAt: DomainTimestamp(DateTime.utc(2026, 8, 15)),
          deviceId: 'dev-test',
          schemaVersion: 1,
        ),
      );
      await store.append(tx);
      projections.apply(tx);
      eventBus.publish(tx);

      final updated = await container.read(fundingPaceProvider(august).future);
      expect(updated.rows.single.row.contributedThisMonthUsdCents, 25000);
    });
  });
}
