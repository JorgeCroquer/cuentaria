import 'package:test/test.dart';
import 'package:contabilidad/domain/transaccion.dart';
import 'package:contabilidad/domain/transaccion_metadata.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:contabilidad/domain/saldo_cuenta.dart';
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

    test(
      'Property Test: Extracción proporcional de costo base y residuo cero (C1-6)',
      () {
        final projections = InMemoryLedgerProjections();
        final accBsId = AccountId('acc-bs');

        // Simulamos múltiples adquisiciones (compras de Bs con USD)
        // Adquisición 1: Compramos 4000 Bs por $100
        projections.aplicar(
          Transaccion.crear(
            postings: [
              Posting(
                target: CuentaTarget(AccountId('acc-usd')),
                amountNative: Money(
                  amount: BigInt.from(-10000),
                  currency: CurrencyCode('USD'),
                ),
                currency: CurrencyCode('USD'),
                amountUsd: -10000,
              ),
              Posting(
                target: CuentaTarget(accBsId),
                amountNative: Money(
                  amount: BigInt.from(400000),
                  currency: CurrencyCode('VES'),
                ), // 4000.00
                currency: CurrencyCode('VES'),
                amountUsd: 10000, // $100.00
              ),
            ],
            metadata: TransaccionMetadata(
              eventId: EventId('e1'),
              tipo: 'ConversionAdquisicion',
              occurredAt: DomainTimestamp(DateTime.now().toUtc()),
              recordedAt: DomainTimestamp(DateTime.now().toUtc()),
              deviceId: 'd1',
              schemaVersion: 1,
            ),
          ),
        );

        // Adquisición 2: Compramos 2000 Bs por $60 (tasa distinta)
        projections.aplicar(
          Transaccion.crear(
            postings: [
              Posting(
                target: CuentaTarget(AccountId('acc-usd')),
                amountNative: Money(
                  amount: BigInt.from(-6000),
                  currency: CurrencyCode('USD'),
                ),
                currency: CurrencyCode('USD'),
                amountUsd: -6000,
              ),
              Posting(
                target: CuentaTarget(accBsId),
                amountNative: Money(
                  amount: BigInt.from(200000),
                  currency: CurrencyCode('VES'),
                ), // 2000.00
                currency: CurrencyCode('VES'),
                amountUsd: 6000, // $60.00
              ),
            ],
            metadata: TransaccionMetadata(
              eventId: EventId('e2'),
              tipo: 'ConversionAdquisicion',
              occurredAt: DomainTimestamp(DateTime.now().toUtc()),
              recordedAt: DomainTimestamp(DateTime.now().toUtc()),
              deviceId: 'd1',
              schemaVersion: 1,
            ),
          ),
        );

        final saldoTotal = projections.saldoCuenta(accBsId);
        expect(
          saldoTotal.native.amount,
          equals(BigInt.from(600000)),
        ); // 6000.00 Bs
        expect(saldoTotal.usd, equals(16000)); // $160.00

        // Extracción fraccionada: gastamos 1500 Bs, luego 3000 Bs, luego el resto (1500 Bs)
        final costo1 = saldoTotal.costoBaseDe(BigInt.from(150000));
        final costo2 = saldoTotal.costoBaseDe(BigInt.from(300000));

        // El último retiro debe usar la regla cero-native y vaciar el saldo
        // Usamos el total y le restamos lo que ya extrajimos para simular el remanente en la vida real
        final remanenteNative = saldoTotal.native.amount - BigInt.from(450000);

        // Pero espera, el método `costoBaseDe` sobre el saldo original siempre calcula proporciones.
        // Para probar la acumulación exacta sin perder centavos, tenemos que simular
        // que el saldo VA BAJANDO después de cada extracción, que es como el sistema opera.

        // Retiro 1
        final saldoDespues1 = SaldoCuenta(
          native: Money(
            amount: saldoTotal.native.amount - BigInt.from(150000),
            currency: CurrencyCode('VES'),
          ),
          usd: saldoTotal.usd - costo1,
        );

        // Retiro 2
        final costo2Real = saldoDespues1.costoBaseDe(BigInt.from(300000));
        final saldoDespues2 = SaldoCuenta(
          native: Money(
            amount: saldoDespues1.native.amount - BigInt.from(300000),
            currency: CurrencyCode('VES'),
          ),
          usd: saldoDespues1.usd - costo2Real,
        );

        // Retiro final (todo el remanente)
        final costo3Real = saldoDespues2.costoBaseDe(
          saldoDespues2.native.amount,
        ); // C1-6 Zero-Native
        final saldoFinal = SaldoCuenta(
          native: Money(amount: BigInt.zero, currency: CurrencyCode('VES')),
          usd: saldoDespues2.usd - costo3Real,
        );

        // Verificamos que la suma de todos los costos base extraídos sea exactamente el costo inicial en USD
        final sumaCostos = costo1 + costo2Real + costo3Real;
        expect(sumaCostos, equals(16000));

        expect(saldoFinal.native.amount, equals(BigInt.zero));
        expect(saldoFinal.usd, equals(0));
      },
    );

    test('limpiar reinicia los saldos a cero', () {
      final projections = InMemoryLedgerProjections();
      final accId = AccountId('acc-1');
      final envId = EnvelopeId('env-1');

      final tx = Transaccion.crear(
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
            target: SobreTarget(envId),
            amountNative: Money(
              amount: BigInt.from(100),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: 100,
          ),
        ],
        metadata: TransaccionMetadata(
          eventId: EventId('evt-123'),
          tipo: 'Ingreso',
          occurredAt: DomainTimestamp(DateTime.now().toUtc()),
          recordedAt: DomainTimestamp(DateTime.now().toUtc()),
          deviceId: 'device-1',
          schemaVersion: 1,
        ),
      );

      projections.aplicar(tx);
      expect(projections.saldoCuenta(accId).usd, equals(100));
      expect(projections.saldoUsdSobre(envId), equals(100));

      projections.limpiar();

      expect(projections.saldoCuenta(accId).usd, equals(0));
      expect(projections.saldoCuenta(accId).native.amount, equals(BigInt.zero));
      expect(projections.saldoUsdSobre(envId), equals(0));
    });
  });
}
