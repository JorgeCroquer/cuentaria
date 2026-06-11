import 'package:test/test.dart';
import 'package:contabilidad/domain/transaccion.dart';
import 'package:contabilidad/domain/transaccion_metadata.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';

void main() {
  group('InMemoryLedgerProjections', () {
    test('aplicar incrementa saldos correctamente', () {
      final projections = InMemoryLedgerProjections();

      final accId = AccountId('acc-1');
      final envId = EnvelopeId('env-1');

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
          target: CuentaTarget(accId),
          amountNative: Money(
            amount: BigInt.from(100),
            currency: CurrencyCode('USD'),
          ),
          currency: CurrencyCode('USD'),
          amountUsd: 100,
        ),
        Posting(
          target: SobreTarget(envId),
          amountNative: Money(
            amount: BigInt.from(100),
            currency: CurrencyCode('USD'),
          ),
          currency: CurrencyCode('USD'),
          amountUsd: 100,
        ),
      ];

      final tx = Transaccion.crear(postings: postings, metadata: metadata);

      projections.aplicar(tx);

      final saldoCuenta = projections.saldoCuenta(accId);
      expect(
        saldoCuenta.native,
        equals(Money(amount: BigInt.from(100), currency: CurrencyCode('USD'))),
      );
      expect(saldoCuenta.usd, equals(100));

      final saldoSobre = projections.saldoUsdSobre(envId);
      expect(saldoSobre, equals(100));

      // Aplicar otra que sume a las mismas
      final metadata2 = TransaccionMetadata(
        eventId: EventId('evt-124'),
        tipo: 'Ingreso',
        occurredAt: DomainTimestamp(DateTime.utc(2026, 6, 11)),
        recordedAt: DomainTimestamp(DateTime.utc(2026, 6, 11, 12)),
        deviceId: 'device-1',
        schemaVersion: 1,
      );

      final tx2 = Transaccion.crear(postings: postings, metadata: metadata2);
      projections.aplicar(tx2);

      final saldoCuenta2 = projections.saldoCuenta(accId);
      expect(
        saldoCuenta2.native,
        equals(Money(amount: BigInt.from(200), currency: CurrencyCode('USD'))),
      );
      expect(saldoCuenta2.usd, equals(200));

      final saldoSobre2 = projections.saldoUsdSobre(envId);
      expect(saldoSobre2, equals(200));
    });

    test(
      'aplicar lanza StateError si misma cuenta recibe monedas distintas',
      () {
        final projections = InMemoryLedgerProjections();
        final accId = AccountId('acc-1');

        final tx1 = Transaccion.crear(
          postings: [
            Posting(
              target: CuentaTarget(accId),
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
          metadata: TransaccionMetadata(
            eventId: EventId('evt-200'),
            tipo: 'Ingreso',
            occurredAt: DomainTimestamp(DateTime.utc(2026, 6, 11)),
            recordedAt: DomainTimestamp(DateTime.utc(2026, 6, 11, 12)),
            deviceId: 'device-1',
            schemaVersion: 1,
          ),
        );

        projections.aplicar(tx1);

        final tx2 = Transaccion.crear(
          postings: [
            Posting(
              target: CuentaTarget(accId),
              amountNative: Money(
                amount: BigInt.from(5000),
                currency: CurrencyCode('VES'),
              ),
              currency: CurrencyCode('VES'),
              amountUsd: 100,
            ),
            Posting(
              target: SobreTarget(EnvelopeId('env-1')),
              amountNative: Money(
                amount: BigInt.from(5000),
                currency: CurrencyCode('VES'),
              ),
              currency: CurrencyCode('VES'),
              amountUsd: 100,
            ),
          ],
          metadata: TransaccionMetadata(
            eventId: EventId('evt-201'),
            tipo: 'Ingreso',
            occurredAt: DomainTimestamp(DateTime.utc(2026, 6, 11)),
            recordedAt: DomainTimestamp(DateTime.utc(2026, 6, 11, 12)),
            deviceId: 'device-1',
            schemaVersion: 1,
          ),
        );

        expect(() => projections.aplicar(tx2), throwsStateError);
      },
    );
  });
}
