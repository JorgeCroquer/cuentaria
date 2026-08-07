import 'package:contabilidad/application/cascade/cascade.dart';
import 'package:contabilidad/application/cascade/cascade_step.dart';
import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/catalog/models/funding_target.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:contabilidad/infrastructure/cascade/in_memory_cascade_repository.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:cuentaria_app/features/backup/application/create_backup.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/domain/rate_observation.dart';
import 'package:tasas/infrastructure/in_memory/in_memory_rate_series.dart';

Transaction _makeTx(String eventId) => Transaction.create(
  metadata: TransactionMetadata(
    eventId: EventId(eventId),
    type: 'Income',
    occurredAt: DomainTimestamp(DateTime.utc(2026, 8, 1)),
    recordedAt: DomainTimestamp(DateTime.utc(2026, 8, 1, 0, 1)),
    deviceId: 'device-test',
    schemaVersion: 1,
  ),
  postings: [
    Posting(
      target: AccountTarget(AccountId('acc-1')),
      amountNative: Money(
        amount: BigInt.from(1000),
        currency: CurrencyCode('USD'),
      ),
      currency: CurrencyCode('USD'),
      amountUsd: 1000,
    ),
    Posting(
      target: EnvelopeTarget(EnvelopeId('env-1')),
      amountNative: Money(
        amount: BigInt.from(1000),
        currency: CurrencyCode('USD'),
      ),
      currency: CurrencyCode('USD'),
      amountUsd: 1000,
    ),
  ],
);

void main() {
  test(
    'reads all four ports and writes a Backup File with matching counts',
    () async {
      final eventStore = InMemoryEventStore();
      await eventStore.append(_makeTx('evt-1'));
      await eventStore.append(_makeTx('evt-2'));

      final catalog = InMemoryCatalogRepository();
      await catalog.saveAccount(
        Account(
          id: AccountId('acc-1'),
          name: 'Efectivo',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.utc(2026, 8, 1),
          meta: const {'color': '#00FF00'},
        ),
      );
      await catalog.saveEnvelope(
        Envelope(
          id: EnvelopeId('env-1'),
          name: 'Alquiler',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.utc(2026, 8, 1),
        ).withTarget(const Cap(amountUsd: 50000)),
      );

      final cascadeRepo = InMemoryCascadeRepository();
      await cascadeRepo.save(
        Cascade(
          steps: [CascadeStep.fillToCap(envelopeId: EnvelopeId('env-1'))],
          updatedAt: DateTime.utc(2026, 8, 2),
        ),
      );

      final rateSeries = InMemoryRateSeries();
      await rateSeries.append(
        RateObservation(
          currency: CurrencyCode('VES'),
          nativePerUsd: Decimal.parse('36.5'),
          observedAt: DateTime.utc(2026, 8, 6),
          source: 'manual:bcv',
        ),
      );

      final createBackup = CreateBackup(
        eventStore: eventStore,
        catalog: catalog,
        cascade: cascadeRepo,
        rates: rateSeries,
        now: () => DateTime.utc(2026, 8, 7, 14, 3),
      );

      final result = await createBackup();

      expect(result.filename, equals('cuentaria-2026-08-07.ndjson'));
      expect(result.counts.event, equals(2));
      expect(result.counts.account, equals(1));
      // InMemoryCatalogRepository auto-seeds 4 system envelopes on top of
      // the one user envelope saved above.
      expect(result.counts.envelope, equals(5));
      expect(result.counts.cascade, equals(1));
      expect(result.counts.rate, equals(1));

      // Catalog survives with meta (account color, envelope Cap).
      expect(result.content, contains('"color":"#00FF00"'));
      expect(result.content, contains('"type":"cap"'));
      expect(result.content, contains('"amount_usd":50000'));

      // app_meta (device_id, last_backup_date) never appears in the file —
      // it identifies this install, not a fact of the user's finances.
      expect(result.content, isNot(contains('last_backup_date')));
      expect(result.content, isNot(contains('"kind":"app_meta"')));

      final lines = result.content.split('\n');
      expect(lines.first, contains('"kind":"header"'));
      expect(lines.first, contains('"format":1'));
    },
  );

  test(
    'an envelope with no target/appearance omits meta, not a null',
    () async {
      final catalog = InMemoryCatalogRepository();
      await catalog.saveAccount(
        Account(
          id: AccountId('acc-1'),
          name: 'Efectivo',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.utc(2026, 8, 1),
        ),
      );

      final createBackup = CreateBackup(
        eventStore: InMemoryEventStore(),
        catalog: catalog,
        cascade: InMemoryCascadeRepository(),
        rates: InMemoryRateSeries(),
        now: () => DateTime.utc(2026, 8, 7),
      );

      final result = await createBackup();
      expect(result.counts.account, equals(1));
      expect(result.content, isNot(contains('EnvelopeAppearance')));
    },
  );

  test('312 movements produce a backup in under 2s and under 200KB', () async {
    final eventStore = InMemoryEventStore();
    for (var i = 0; i < 312; i++) {
      await eventStore.append(_makeTx('evt-$i'));
    }

    final createBackup = CreateBackup(
      eventStore: eventStore,
      catalog: InMemoryCatalogRepository(),
      cascade: InMemoryCascadeRepository(),
      rates: InMemoryRateSeries(),
      now: () => DateTime.utc(2026, 8, 7),
    );

    final stopwatch = Stopwatch()..start();
    final result = await createBackup();
    stopwatch.stop();

    expect(result.counts.event, equals(312));
    expect(stopwatch.elapsedMilliseconds, lessThan(2000));
    expect(result.content.codeUnits.length, lessThan(200 * 1024));
  });
}
