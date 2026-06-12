import 'package:test/test.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:contabilidad/domain/transaccion.dart';
import 'package:contabilidad/domain/transaccion_metadata.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:contabilidad/application/ledger/reconstruir_proyecciones.dart';

void main() {
  group('ReconstruirProyecciones', () {
    test('limpia y reconstruye idéntico desde el log de eventos', () async {
      final store = InMemoryEventStore();
      final projections = InMemoryLedgerProjections();

      Transaccion createTx(String id, int amount) {
        return Transaccion.crear(
          metadata: TransaccionMetadata(
            eventId: EventId(id),
            tipo: 'Test',
            occurredAt: DomainTimestamp(DateTime.utc(2026, 6, 1)),
            recordedAt: DomainTimestamp(DateTime.utc(2026, 6, 1)),
            deviceId: 'dev',
            schemaVersion: 1,
          ),
          postings: [
            Posting(
              target: CuentaTarget(AccountId('acc-1')),
              amountNative: Money(amount: BigInt.from(amount), currency: CurrencyCode('USD')),
              currency: CurrencyCode('USD'),
              amountUsd: amount,
            ),
            Posting(
              target: SobreTarget(EnvelopeId('env-1')),
              amountNative: Money(amount: BigInt.from(amount), currency: CurrencyCode('USD')),
              currency: CurrencyCode('USD'),
              amountUsd: amount,
            ),
          ],
        );
      }

      final tx1 = createTx('evt-1', 100);
      final tx2 = createTx('evt-2', 200);

      // Simular registro inicial incremental
      await store.append(tx1);
      projections.aplicar(tx1);
      
      await store.append(tx2);
      projections.aplicar(tx2);

      final saldoUsdOriginal = projections.saldoCuenta(AccountId('acc-1'));
      final saldoSobreOriginal = projections.saldoUsdSobre(EnvelopeId('env-1'));

      expect(saldoUsdOriginal.usd, equals(300));
      expect(saldoSobreOriginal, equals(300));

      // Limpiar (descartar estado)
      projections.limpiar();
      expect(projections.saldoCuenta(AccountId('acc-1')).usd, equals(0));
      expect(projections.saldoUsdSobre(EnvelopeId('env-1')), equals(0));

      // Ejecutar caso de uso (todavía no implementado, fallará aquí)
      final reconstructor = ReconstruirProyecciones(
        store: store,
        projections: projections,
      );
      
      await reconstructor.execute();

      // Verificar que se reconstruyó exacto
      final saldoUsdReconstruido = projections.saldoCuenta(AccountId('acc-1'));
      final saldoSobreReconstruido = projections.saldoUsdSobre(EnvelopeId('env-1'));

      expect(saldoUsdReconstruido.native.amount, equals(saldoUsdOriginal.native.amount));
      expect(saldoUsdReconstruido.usd, equals(saldoUsdOriginal.usd));

      expect(saldoSobreReconstruido, equals(saldoSobreOriginal));
    });

    test('Property Test: auto-heal y estado idéntico tras replay con eventos retrofechados', () async {
      final store = InMemoryEventStore();
      final incrementalProjections = InMemoryLedgerProjections();
      final replayProjections = InMemoryLedgerProjections();

      Transaccion createTx(String id, int amount, DateTime occurred) {
        return Transaccion.crear(
          metadata: TransaccionMetadata(
            eventId: EventId(id),
            tipo: 'Test',
            occurredAt: DomainTimestamp(occurred),
            recordedAt: DomainTimestamp(DateTime.now().toUtc()), // Insertado ahora
            deviceId: 'dev',
            schemaVersion: 1,
          ),
          postings: [
            Posting(
              target: CuentaTarget(AccountId('acc-property')),
              amountNative: Money(amount: BigInt.from(amount), currency: CurrencyCode('USD')),
              currency: CurrencyCode('USD'),
              amountUsd: amount,
            ),
            Posting(
              target: SobreTarget(EnvelopeId('env-property')),
              amountNative: Money(amount: BigInt.from(amount), currency: CurrencyCode('USD')),
              currency: CurrencyCode('USD'),
              amountUsd: amount,
            ),
          ],
        );
      }

      // El evento 1 ocurre el día 2
      final tx1 = createTx('evt-day-2', 100, DateTime.utc(2026, 6, 2));
      // El evento 2 ocurre el día 3
      final tx2 = createTx('evt-day-3', 200, DateTime.utc(2026, 6, 3));
      // El evento 3 OCURRE EL DÍA 1 (RETROFECHADO), pero se registra al final
      final tx3 = createTx('evt-day-1', 50, DateTime.utc(2026, 6, 1));

      // Orden de inserción/llegada (incrementalProjections aplica en este orden)
      await store.append(tx1);
      incrementalProjections.aplicar(tx1);

      await store.append(tx2);
      incrementalProjections.aplicar(tx2);

      await store.append(tx3);
      incrementalProjections.aplicar(tx3);

      final accountId = AccountId('acc-property');
      final envelopeId = EnvelopeId('env-property');

      final incCuenta = incrementalProjections.saldoCuenta(accountId);
      final incSobre = incrementalProjections.saldoUsdSobre(envelopeId);

      // El acumulado total es la suma de los montos congelados (conmutativa) => 100+200+50 = 350
      expect(incCuenta.usd, equals(350));
      expect(incSobre, equals(350));

      // Replay
      final reconstructor = ReconstruirProyecciones(
        store: store,
        projections: replayProjections,
      );
      await reconstructor.execute();

      final repCuenta = replayProjections.saldoCuenta(accountId);
      final repSobre = replayProjections.saldoUsdSobre(envelopeId);

      // Verificamos que a pesar del orden distinto de aplicación, el estado es idéntico
      expect(repCuenta.native.amount, equals(incCuenta.native.amount));
      expect(repCuenta.usd, equals(incCuenta.usd));
      expect(repSobre, equals(incSobre));
    });
  });
}
