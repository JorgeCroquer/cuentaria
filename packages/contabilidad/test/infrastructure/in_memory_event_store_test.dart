import 'package:test/test.dart';
import 'package:contabilidad/domain/transaccion.dart';
import 'package:contabilidad/domain/transaccion_metadata.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';

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

      final txOrig = Transaccion.crear(postings: postingsOrig, metadata: metadataOrig);
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

      final txRev = Transaccion.crear(postings: postingsOrig, metadata: metadataRev);
      await store.append(txRev);

      // hasReversal() after reversal
      expect(await store.hasReversal(EventId('evt-orig')), isTrue);
    });
  });
}
