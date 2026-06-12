import 'package:test/test.dart';
import 'package:contabilidad/domain/transaccion.dart';
import 'package:contabilidad/domain/transaccion_metadata.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/domain/ports/filtros_log.dart';

void main() {
  group('InMemoryEventStore', () {
    test('append retorna true al insertar y false al duplicar', () async {
      final store = InMemoryEventStore();

      final metadata = TransaccionMetadata(
        eventId: EventId('evt-123'),
        tipo: 'Ingreso',
        occurredAt: DomainTimestamp(DateTime.utc(2026, 6, 11)),
        recordedAt: DomainTimestamp(DateTime.utc(2026, 6, 11, 12)),
        deviceId: 'device-1',
        schemaVersion: 1,
      );

      final postings = [
        Posting(
          target: CuentaTarget(AccountId('acc-1')),
          amountNative: Money(
            amount: BigInt.from(100),
            currency: CurrencyCode('USD'),
          ),
          currency: CurrencyCode('USD'),
          amountUsd: 100,
        ),
        Posting(
          target: SobreTarget(EnvelopeId('env-1')),
          amountNative: Money(
            amount: BigInt.from(100),
            currency: CurrencyCode('USD'),
          ),
          currency: CurrencyCode('USD'),
          amountUsd: 100,
        ),
      ];

      final tx = Transaccion.crear(postings: postings, metadata: metadata);

      // Primer insert
      final result1 = await store.append(tx);
      expect(result1, isTrue);

      // Segundo insert del mismo event_id
      final result2 = await store.append(tx);
      expect(result2, isFalse);

      // Verificamos que no haya guardado duplicados
      expect(store.events.length, equals(1));
    });

    test('get y hasReversal funcionan correctamente', () async {
      final store = InMemoryEventStore();

      final metadataOrig = TransaccionMetadata(
        eventId: EventId('evt-orig'),
        tipo: 'Ingreso',
        occurredAt: DomainTimestamp(DateTime.utc(2026, 6, 11)),
        recordedAt: DomainTimestamp(DateTime.utc(2026, 6, 11, 12)),
        deviceId: 'device-1',
        schemaVersion: 1,
      );

      final postingsOrig = [
        Posting(
          target: CuentaTarget(AccountId('acc-1')),
          amountNative: Money(
            amount: BigInt.from(100),
            currency: CurrencyCode('USD'),
          ),
          currency: CurrencyCode('USD'),
          amountUsd: 100,
        ),
        Posting(
          target: SobreTarget(EnvelopeId('env-1')),
          amountNative: Money(
            amount: BigInt.from(100),
            currency: CurrencyCode('USD'),
          ),
          currency: CurrencyCode('USD'),
          amountUsd: 100,
        ),
      ];

      final txOrig = Transaccion.crear(
        postings: postingsOrig,
        metadata: metadataOrig,
      );
      await store.append(txOrig);

      // get()
      final retrieved = await store.get(EventId('evt-orig'));
      expect(retrieved, isNotNull);
      expect(retrieved?.metadata.eventId.value, equals('evt-orig'));

      final missing = await store.get(EventId('evt-missing'));
      expect(missing, isNull);

      // hasReversal() before reversal
      expect(await store.hasReversal(EventId('evt-orig')), isFalse);

      final metadataRev = TransaccionMetadata(
        eventId: EventId('evt-rev'),
        tipo: 'Reverso',
        reverses: EventId('evt-orig'),
        occurredAt: DomainTimestamp(DateTime.utc(2026, 6, 11)),
        recordedAt: DomainTimestamp(DateTime.utc(2026, 6, 11, 13)),
        deviceId: 'device-1',
        schemaVersion: 1,
      );

      final txRev = Transaccion.crear(
        postings: postingsOrig,
        metadata: metadataRev,
      );
      await store.append(txRev);

      // hasReversal() after reversal
      expect(await store.hasReversal(EventId('evt-orig')), isTrue);
    });

    test('consultarLog filtra por cuenta, sobre y rango de fechas', () async {
      final store = InMemoryEventStore();

      Transaccion createTx(
        String id,
        DateTime occurred,
        String accId,
        String envId,
      ) {
        return Transaccion.crear(
          metadata: TransaccionMetadata(
            eventId: EventId(id),
            tipo: 'Test',
            occurredAt: DomainTimestamp(occurred),
            recordedAt: DomainTimestamp(occurred),
            deviceId: 'dev',
            schemaVersion: 1,
          ),
          postings: [
            Posting(
              target: CuentaTarget(AccountId(accId)),
              amountNative: Money(
                amount: BigInt.from(100),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: 100,
            ),
            Posting(
              target: SobreTarget(EnvelopeId(envId)),
              amountNative: Money(
                amount: BigInt.from(100),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: 100,
            ),
          ],
        );
      }

      await store.append(
        createTx('tx1', DateTime.utc(2026, 6, 10), 'acc-1', 'env-1'),
      );
      await store.append(
        createTx('tx2', DateTime.utc(2026, 6, 11), 'acc-2', 'env-2'),
      );
      await store.append(
        createTx('tx3', DateTime.utc(2026, 6, 12), 'acc-1', 'env-2'),
      );
      await store.append(
        createTx('tx4', DateTime.utc(2026, 6, 13), 'acc-3', 'env-1'),
      );

      // Filter by cuenta
      final byCuenta = await store.consultarLog(
        filtros: FiltrosLog(cuenta: AccountId('acc-1')),
      );
      expect(
        byCuenta.map((e) => e.metadata.eventId.value).toList(),
        equals(['tx1', 'tx3']),
      );

      // Filter by sobre
      final bySobre = await store.consultarLog(
        filtros: FiltrosLog(sobre: EnvelopeId('env-2')),
      );
      expect(
        bySobre.map((e) => e.metadata.eventId.value).toList(),
        equals(['tx2', 'tx3']),
      );

      // Filter by date range (inclusive)
      final byDate = await store.consultarLog(
        filtros: FiltrosLog(
          desde: DomainTimestamp(DateTime.utc(2026, 6, 11)),
          hasta: DomainTimestamp(DateTime.utc(2026, 6, 12)),
        ),
      );
      expect(
        byDate.map((e) => e.metadata.eventId.value).toList(),
        equals(['tx2', 'tx3']),
      );

      // Filter combined (cuenta and date)
      final combined = await store.consultarLog(
        filtros: FiltrosLog(
          cuenta: AccountId('acc-1'),
          desde: DomainTimestamp(DateTime.utc(2026, 6, 11)),
        ),
      );
      expect(
        combined.map((e) => e.metadata.eventId.value).toList(),
        equals(['tx3']),
      );
    });

    test(
      'consultarLog retorna eventos con ordenamiento determinista total',
      () async {
        final store = InMemoryEventStore();

        Transaccion createTx(String id, DateTime occurred, DateTime recorded) {
          return Transaccion.crear(
            metadata: TransaccionMetadata(
              eventId: EventId(id),
              tipo: 'Test',
              occurredAt: DomainTimestamp(occurred),
              recordedAt: DomainTimestamp(recorded),
              deviceId: 'dev',
              schemaVersion: 1,
            ),
            postings: [
              Posting(
                target: CuentaTarget(AccountId('acc-1')),
                amountNative: Money(
                  amount: BigInt.from(100),
                  currency: CurrencyCode('USD'),
                ),
                currency: CurrencyCode('USD'),
                amountUsd: 100,
              ),
              Posting(
                target: SobreTarget(EnvelopeId('env-1')),
                amountNative: Money(
                  amount: BigInt.from(100),
                  currency: CurrencyCode('USD'),
                ),
                currency: CurrencyCode('USD'),
                amountUsd: 100,
              ),
            ],
          );
        }

        // We append in an arbitrary order
        // eventId 'evt-A', occurredAt day 3, recordedAt day 3
        await store.append(
          createTx('evt-A', DateTime.utc(2026, 6, 3), DateTime.utc(2026, 6, 3)),
        );

        // eventId 'evt-B', occurredAt day 1, recordedAt day 1
        await store.append(
          createTx('evt-B', DateTime.utc(2026, 6, 1), DateTime.utc(2026, 6, 1)),
        );

        // eventId 'evt-C', occurredAt day 2, recordedAt day 5
        await store.append(
          createTx('evt-C', DateTime.utc(2026, 6, 2), DateTime.utc(2026, 6, 5)),
        );

        // eventId 'evt-D', occurredAt day 2, recordedAt day 4
        await store.append(
          createTx('evt-D', DateTime.utc(2026, 6, 2), DateTime.utc(2026, 6, 4)),
        );

        // eventId 'evt-Z', occurredAt day 2, recordedAt day 4
        // Tie with evt-D on occurredAt and recordedAt, so eventId breaks tie (evt-D < evt-Z)
        await store.append(
          createTx('evt-Z', DateTime.utc(2026, 6, 2), DateTime.utc(2026, 6, 4)),
        );

        final results = await store.consultarLog();

        // Expected order:
        // 1. evt-B (occurred: 6/1)
        // 2. evt-D (occurred: 6/2, recorded: 6/4, id: evt-D)
        // 3. evt-Z (occurred: 6/2, recorded: 6/4, id: evt-Z)
        // 4. evt-C (occurred: 6/2, recorded: 6/5)
        // 5. evt-A (occurred: 6/3)

        final orderedIds =
            results.map((e) => e.metadata.eventId.value).toList();
        expect(
          orderedIds,
          equals(['evt-B', 'evt-D', 'evt-Z', 'evt-C', 'evt-A']),
        );
      },
    );
  });
}
