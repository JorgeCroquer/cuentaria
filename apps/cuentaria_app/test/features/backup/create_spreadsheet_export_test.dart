import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:cuentaria_app/features/backup/application/create_spreadsheet_export.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';

Transaction _expenseTx(
  String eventId, {
  int amountUsd = 1182,
  BigInt? amountNative,
  CurrencyCode? currency,
  String? memo,
  String? rateRef,
}) {
  final money = Money(
    amount: -(amountNative ?? BigInt.from(amountUsd)),
    currency: currency ?? CurrencyCode('USD'),
  );
  return Transaction.create(
    metadata: TransactionMetadata(
      eventId: EventId(eventId),
      type: 'Expense',
      occurredAt: DomainTimestamp(DateTime.utc(2026, 8, 1)),
      recordedAt: DomainTimestamp(DateTime.utc(2026, 8, 1, 0, 1)),
      deviceId: 'device-test',
      schemaVersion: 1,
      memo: memo,
    ),
    postings: [
      Posting(
        target: AccountTarget(AccountId('acc-1')),
        amountNative: money,
        currency: money.currency,
        amountUsd: -amountUsd,
        rateRef: rateRef,
      ),
      Posting(
        target: EnvelopeTarget(EnvelopeId('env-1')),
        amountNative: Money(
          amount: BigInt.from(amountUsd),
          currency: CurrencyCode('USD'),
        ),
        currency: CurrencyCode('USD'),
        amountUsd: -amountUsd,
      ),
    ],
  );
}

void main() {
  test('flattens a two-leg transaction into two CSV rows', () async {
    final eventStore = InMemoryEventStore();
    await eventStore.append(_expenseTx('evt-1'));

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
    await catalog.saveEnvelope(
      Envelope(
        id: EnvelopeId('env-1'),
        name: 'Alquiler',
        role: EnvelopeRole.none,
        isArchived: false,
        updatedAt: DateTime.utc(2026, 8, 1),
      ),
    );

    final createExport = CreateSpreadsheetExport(
      eventStore: eventStore,
      catalog: catalog,
      now: () => DateTime.utc(2026, 8, 7),
    );

    final result = await createExport();

    expect(result.filename, equals('cuentaria-2026-08-07.csv'));
    expect(result.rowCount, equals(2));

    final lines = result.content.split('\n');
    expect(lines.first, startsWith('fecha,tipo,memo,dimension,nombre,'));
    expect(lines, hasLength(3));
    expect(lines[1], contains('cuenta,Efectivo'));
    expect(lines[2], contains('sobre,Alquiler'));
    expect(lines[1], contains('evt-1'));
    expect(lines[2], contains('evt-1'));
  });

  test('flattens a one-to-three distribution into four CSV rows', () async {
    final eventStore = InMemoryEventStore();
    final envOrigen = EnvelopeId('env-origen');
    final envDestino1 = EnvelopeId('env-destino-1');
    final envDestino2 = EnvelopeId('env-destino-2');
    final envDestino3 = EnvelopeId('env-destino-3');

    await eventStore.append(
      Transaction.create(
        metadata: TransactionMetadata(
          eventId: EventId('evt-distribucion'),
          type: 'Distribution',
          occurredAt: DomainTimestamp(DateTime.utc(2026, 8, 1)),
          recordedAt: DomainTimestamp(DateTime.utc(2026, 8, 1, 0, 1)),
          deviceId: 'device-test',
          schemaVersion: 1,
        ),
        postings: [
          Posting(
            target: EnvelopeTarget(envOrigen),
            amountNative: Money(
              amount: BigInt.from(-150),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: -150,
          ),
          Posting(
            target: EnvelopeTarget(envDestino1),
            amountNative: Money(
              amount: BigInt.from(50),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: 50,
          ),
          Posting(
            target: EnvelopeTarget(envDestino2),
            amountNative: Money(
              amount: BigInt.from(50),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: 50,
          ),
          Posting(
            target: EnvelopeTarget(envDestino3),
            amountNative: Money(
              amount: BigInt.from(50),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: 50,
          ),
        ],
      ),
    );

    final catalog = InMemoryCatalogRepository();
    for (final entry
        in {
          envOrigen: 'Origen',
          envDestino1: 'Destino 1',
          envDestino2: 'Destino 2',
          envDestino3: 'Destino 3',
        }.entries) {
      await catalog.saveEnvelope(
        Envelope(
          id: entry.key,
          name: entry.value,
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.utc(2026, 8, 1),
        ),
      );
    }

    final createExport = CreateSpreadsheetExport(
      eventStore: eventStore,
      catalog: catalog,
      now: () => DateTime.utc(2026, 8, 7),
    );

    final result = await createExport();

    expect(result.rowCount, equals(4));
    final lines = result.content.split('\n');
    expect(lines, hasLength(5));
    final dataLines = lines.skip(1);
    expect(dataLines, everyElement(contains('evt-distribucion')));
    expect(dataLines, everyElement(contains('sobre,')));
    expect(dataLines.elementAt(0), contains('Origen'));
    expect(dataLines.elementAt(1), contains('Destino 1'));
    expect(dataLines.elementAt(2), contains('Destino 2'));
    expect(dataLines.elementAt(3), contains('Destino 3'));
  });

  test('resolves an archived account name from the catalog', () async {
    final eventStore = InMemoryEventStore();
    await eventStore.append(_expenseTx('evt-1'));

    final catalog = InMemoryCatalogRepository();
    await catalog.saveAccount(
      Account(
        id: AccountId('acc-1'),
        name: 'Cuenta vieja',
        nativeCurrency: CurrencyCode('USD'),
        isArchived: true,
        updatedAt: DateTime.utc(2026, 8, 1),
      ),
    );
    await catalog.saveEnvelope(
      Envelope(
        id: EnvelopeId('env-1'),
        name: 'Alquiler',
        role: EnvelopeRole.none,
        isArchived: false,
        updatedAt: DateTime.utc(2026, 8, 1),
      ),
    );

    final createExport = CreateSpreadsheetExport(
      eventStore: eventStore,
      catalog: catalog,
      now: () => DateTime.utc(2026, 8, 7),
    );

    final result = await createExport();

    expect(result.content, contains('Cuenta vieja'));
  });

  test(
    'formats a VES posting as decimal text with its rate reference',
    () async {
      final eventStore = InMemoryEventStore();
      await eventStore.append(
        _expenseTx(
          'evt-1',
          amountUsd: 1182,
          amountNative: BigInt.from(1000000),
          currency: CurrencyCode('VES'),
          rateRef: '845.88 VES/USD',
        ),
      );

      final catalog = InMemoryCatalogRepository();
      await catalog.saveAccount(
        Account(
          id: AccountId('acc-1'),
          name: 'Banco',
          nativeCurrency: CurrencyCode('VES'),
          isArchived: false,
          updatedAt: DateTime.utc(2026, 8, 1),
        ),
      );
      await catalog.saveEnvelope(
        Envelope(
          id: EnvelopeId('env-1'),
          name: 'Alquiler',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.utc(2026, 8, 1),
        ),
      );

      final createExport = CreateSpreadsheetExport(
        eventStore: eventStore,
        catalog: catalog,
        now: () => DateTime.utc(2026, 8, 7),
      );

      final result = await createExport();
      final accountLine = result.content.split('\n')[1];

      expect(accountLine, contains('-10000.00,VES,-11.82,845.88 VES/USD'));
    },
  );

  test('rows come out in canonical occurred_at order', () async {
    final eventStore = InMemoryEventStore();
    final earlier = Transaction.create(
      metadata: TransactionMetadata(
        eventId: EventId('evt-2'),
        type: 'Expense',
        occurredAt: DomainTimestamp(DateTime.utc(2026, 7, 1)),
        recordedAt: DomainTimestamp(DateTime.utc(2026, 7, 1)),
        deviceId: 'device-test',
        schemaVersion: 1,
      ),
      postings: [
        Posting(
          target: AccountTarget(AccountId('acc-1')),
          amountNative: Money(
            amount: BigInt.from(100),
            currency: CurrencyCode('USD'),
          ),
          currency: CurrencyCode('USD'),
          amountUsd: -100,
        ),
        Posting(
          target: EnvelopeTarget(EnvelopeId('env-1')),
          amountNative: Money(
            amount: BigInt.from(100),
            currency: CurrencyCode('USD'),
          ),
          currency: CurrencyCode('USD'),
          amountUsd: -100,
        ),
      ],
    );
    await eventStore.append(_expenseTx('evt-1'));
    await eventStore.append(earlier);

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

    final createExport = CreateSpreadsheetExport(
      eventStore: eventStore,
      catalog: catalog,
      now: () => DateTime.utc(2026, 8, 7),
    );

    final result = await createExport();
    final lines = result.content.split('\n').skip(1).toList();

    expect(lines.first, contains('evt-2'));
    expect(lines.last, contains('evt-1'));
  });
}
