import 'package:test/test.dart';
import 'package:event_bus/event_bus.dart';
import 'package:shared_kernel/shared_kernel.dart';

import 'package:contabilidad/domain/transaccion.dart';
import 'package:contabilidad/domain/transaccion_metadata.dart';
import 'package:contabilidad/domain/transaccion_error.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:contabilidad/application/registrar_transaccion.dart';

void main() {
  group('RegistrarTransaccion', () {
    test(
      'registrar con postings y metadata guarda, proyecta y publica',
      () async {
        final store = InMemoryEventStore();
        final projections = InMemoryLedgerProjections();
        final eventBus = SyncEventBus();

        final registrar = RegistrarTransaccion(
          store: store,
          projections: projections,
          eventBus: eventBus,
        );

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

        final emittedEvents = <DomainEvent>[];
        eventBus.stream
            .where((e) => e is Transaccion)
            .cast<Transaccion>()
            .listen(emittedEvents.add);

        // Call with raw postings+metadata
        await registrar(postings: postings, metadata: metadata);

        expect(store.events.length, equals(1));
        expect(projections.saldoUsdSobre(EnvelopeId('env-1')), equals(100));
        expect(emittedEvents.length, equals(1));

        // Dedup: same event_id again
        await registrar(postings: postings, metadata: metadata);

        expect(store.events.length, equals(1));
        expect(projections.saldoUsdSobre(EnvelopeId('env-1')), equals(100));
        expect(emittedEvents.length, equals(1));
      },
    );

    test('registrar rechaza transacción no balanceada', () async {
      final store = InMemoryEventStore();
      final projections = InMemoryLedgerProjections();
      final eventBus = SyncEventBus();

      final registrar = RegistrarTransaccion(
        store: store,
        projections: projections,
        eventBus: eventBus,
      );

      final metadata = TransaccionMetadata(
        eventId: EventId('evt-400'),
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
            amount: BigInt.from(50),
            currency: CurrencyCode('USD'),
          ),
          currency: CurrencyCode('USD'),
          amountUsd: 50,
        ),
      ];

      expect(
        () => registrar(postings: postings, metadata: metadata),
        throwsA(isA<TransaccionNoBalanceada>()),
      );
    });
  });
}
