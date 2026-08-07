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
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:cuentaria_app/features/backup/application/create_backup.dart';
import 'package:cuentaria_app/features/backup/application/restore_backup.dart';
import 'package:decimal/decimal.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/domain/rate_observation.dart';
import 'package:tasas/infrastructure/in_memory/in_memory_rate_series.dart';

Transaction _makeTx(String eventId, {DateTime? occurredAt}) =>
    Transaction.create(
      metadata: TransactionMetadata(
        eventId: EventId(eventId),
        type: 'Income',
        occurredAt: DomainTimestamp(occurredAt ?? DateTime.utc(2026, 8, 1)),
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

class _Source {
  final eventStore = InMemoryEventStore();
  final catalog = InMemoryCatalogRepository();
  final cascade = InMemoryCascadeRepository();
  final rates = InMemoryRateSeries();

  Future<void> seed() async {
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
    await cascade.save(
      Cascade(
        steps: [CascadeStep.fillToCap(envelopeId: EnvelopeId('env-1'))],
        updatedAt: DateTime.utc(2026, 8, 2),
      ),
    );
    await eventStore.append(_makeTx('evt-1'));
    await eventStore.append(_makeTx('evt-2'));
    await rates.append(
      RateObservation(
        currency: CurrencyCode('VES'),
        nativePerUsd: Decimal.parse('36.5'),
        observedAt: DateTime.utc(2026, 8, 6),
        source: 'manual:bcv',
      ),
    );
  }

  Future<String> backupContent() async {
    final createBackup = CreateBackup(
      eventStore: eventStore,
      catalog: catalog,
      cascade: cascade,
      rates: rates,
      now: () => DateTime.utc(2026, 8, 7),
    );
    return (await createBackup()).content;
  }
}

class _Destination {
  final eventStore = InMemoryEventStore();
  final catalog = InMemoryCatalogRepository();
  final cascade = InMemoryCascadeRepository();
  final rates = InMemoryRateSeries();
  final projections = InMemoryLedgerProjections();
  final eventBus = SyncEventBus();

  RestoreBackup useCase() => RestoreBackup(
    eventStore: eventStore,
    catalog: catalog,
    cascade: cascade,
    rates: rates,
    projections: projections,
    eventBus: eventBus,
  );
}

void main() {
  test(
    'restores onto an empty device: counts and content match the source',
    () async {
      final source = _Source();
      await source.seed();
      final content = await source.backupContent();

      final destination = _Destination();
      final result = await destination.useCase().call(content);

      expect(result.eventsRestored, equals(2));
      expect(destination.eventStore.events, hasLength(2));
      expect(
        destination.catalog.getAccount(AccountId('acc-1'))?.name,
        equals('Efectivo'),
      );
      expect(
        destination.catalog.getEnvelope(EnvelopeId('env-1'))?.target,
        equals(const Cap(amountUsd: 50000)),
      );
      final cascade = await destination.cascade.load();
      expect(cascade?.steps, hasLength(1));
      expect(
        await destination.rates.latestFor(
          CurrencyCode('VES'),
          source: 'manual:bcv',
        ),
        isNotNull,
      );
      // Projections and event bus stay in sync, like every other write path.
      expect(
        destination.projections.accountBalance(AccountId('acc-1')).usd,
        equals(2000),
      );
    },
  );

  test('an unbalanced last event aborts before any write happens', () async {
    final source = _Source();
    await source.seed();
    final content = await source.backupContent();

    // Corrupt the envelope posting's amount on the last event line so it no
    // longer balances against the account posting (ADR-0006 self-balance).
    final lines = content.split('\n');
    final lastEventLineIndex = lines.lastIndexWhere(
      (l) => l.contains('"kind":"event"'),
    );
    final original = lines[lastEventLineIndex];
    final envelopePostingIndex = original.lastIndexOf('"amount_usd":"1000"');
    final before = original.substring(0, envelopePostingIndex);
    final after = original.substring(
      envelopePostingIndex + '"amount_usd":"1000"'.length,
    );
    lines[lastEventLineIndex] = '$before"amount_usd":"999"$after';
    final brokenContent = lines.join('\n');
    expect(brokenContent, isNot(equals(content)));

    final destination = _Destination();
    await expectLater(
      () => destination.useCase().call(brokenContent),
      throwsA(isA<RestoreBackupError>()),
    );

    expect(destination.eventStore.events, isEmpty);
    expect(destination.catalog.accounts, isEmpty);
    expect(await destination.cascade.load(), isNull);
    expect(await destination.rates.allObservations(), isEmpty);
  });

  test(
    'restoring the same file twice does not duplicate events or rates',
    () async {
      final source = _Source();
      await source.seed();
      final content = await source.backupContent();

      final destination = _Destination();
      final first = await destination.useCase().call(content);
      final second = await destination.useCase().call(content);

      expect(first.eventsRestored, equals(2));
      expect(second.eventsRestored, equals(2)); // same message both times
      expect(destination.eventStore.events, hasLength(2));
      expect(await destination.rates.allObservations(), hasLength(1));
    },
  );

  test(
    'restoring onto a device with its own newer data keeps the newer row',
    () async {
      final source = _Source();
      await source.seed();
      final content = await source.backupContent();

      final destination = _Destination();
      await destination.catalog.saveAccount(
        Account(
          id: AccountId('acc-1'),
          name: 'Efectivo (renombrada en destino)',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.utc(
            2026,
            8,
            9,
          ), // newer than the backup's 2026-08-01
        ),
      );
      await destination.catalog.saveAccount(
        Account(
          id: AccountId('acc-2'),
          name: 'Cuenta solo en destino',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.utc(2026, 8, 1),
        ),
      );

      await destination.useCase().call(content);

      expect(
        destination.catalog.getAccount(AccountId('acc-1'))?.name,
        equals('Efectivo (renombrada en destino)'),
      );
      expect(destination.catalog.getAccount(AccountId('acc-2')), isNotNull);
    },
  );

  test('312 movements restore in under 5s', () async {
    final source = _Source();
    for (var i = 0; i < 312; i++) {
      await source.eventStore.append(
        _makeTx('evt-$i', occurredAt: DateTime.utc(2026, 1, 1 + i % 28)),
      );
    }
    await source.catalog.saveAccount(
      Account(
        id: AccountId('acc-1'),
        name: 'Efectivo',
        nativeCurrency: CurrencyCode('USD'),
        isArchived: false,
        updatedAt: DateTime.utc(2026, 8, 1),
      ),
    );
    final content = await source.backupContent();

    final destination = _Destination();
    final stopwatch = Stopwatch()..start();
    final result = await destination.useCase().call(content);
    stopwatch.stop();

    expect(result.eventsRestored, equals(312));
    expect(stopwatch.elapsedMilliseconds, lessThan(5000));
  });
}
