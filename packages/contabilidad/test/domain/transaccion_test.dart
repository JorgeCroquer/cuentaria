import 'package:test/test.dart';
import 'package:contabilidad/domain/transaccion.dart';
import 'package:contabilidad/domain/transaccion_error.dart';
import 'package:contabilidad/domain/transaccion_metadata.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:shared_kernel/shared_kernel.dart';

void main() {
  group('Transaccion', () {
    test('crear lanza TransaccionVacia si postings está vacío', () {
      final metadata = TransaccionMetadata(
        eventId: EventId('evt-123'),
        tipo: 'Ingreso',
        occurredAt: DomainTimestamp(DateTime.utc(2026, 6, 11)),
        recordedAt: DomainTimestamp(DateTime.utc(2026, 6, 11, 12)),
        deviceId: 'device-1',
        schemaVersion: 1,
      );

      expect(
        () => Transaccion.crear(postings: [], metadata: metadata),
        throwsA(isA<TransaccionVacia>()),
      );
    });

    test('crear lanza TransaccionNoBalanceada si montos USD no coinciden', () {
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
            amount: BigInt.from(90),
            currency: CurrencyCode('USD'),
          ),
          currency: CurrencyCode('USD'),
          amountUsd: 90,
        ),
      ];

      expect(
        () => Transaccion.crear(postings: postings, metadata: metadata),
        throwsA(isA<TransaccionNoBalanceada>()),
      );
    });

    test('crear acepta cero-suma de solo dimensión Cuenta (Transferencia)', () {
      final metadata = TransaccionMetadata(
        eventId: EventId('evt-123'),
        tipo: 'Transferencia',
        occurredAt: DomainTimestamp(DateTime.utc(2026, 6, 11)),
        recordedAt: DomainTimestamp(DateTime.utc(2026, 6, 11, 12)),
        deviceId: 'device-1',
        schemaVersion: 1,
      );

      final postings = [
        Posting(
          target: CuentaTarget(AccountId('acc-1')),
          amountNative: Money(
            amount: BigInt.from(-50),
            currency: CurrencyCode('USD'),
          ),
          currency: CurrencyCode('USD'),
          amountUsd: -50,
        ),
        Posting(
          target: CuentaTarget(AccountId('acc-2')),
          amountNative: Money(
            amount: BigInt.from(50),
            currency: CurrencyCode('USD'),
          ),
          currency: CurrencyCode('USD'),
          amountUsd: 50,
        ),
      ];

      final tx = Transaccion.crear(postings: postings, metadata: metadata);
      expect(tx.postings, equals(postings));
    });

    test('crear acepta cero-suma de solo dimensión Sobre (Distribución)', () {
      final metadata = TransaccionMetadata(
        eventId: EventId('evt-124'),
        tipo: 'Distribución',
        occurredAt: DomainTimestamp(DateTime.utc(2026, 6, 11)),
        recordedAt: DomainTimestamp(DateTime.utc(2026, 6, 11, 12)),
        deviceId: 'device-1',
        schemaVersion: 1,
      );

      final postings = [
        Posting(
          target: SobreTarget(EnvelopeId('env-1')),
          amountNative: Money(
            amount: BigInt.from(-30),
            currency: CurrencyCode('USD'),
          ),
          currency: CurrencyCode('USD'),
          amountUsd: -30,
        ),
        Posting(
          target: SobreTarget(EnvelopeId('env-2')),
          amountNative: Money(
            amount: BigInt.from(30),
            currency: CurrencyCode('USD'),
          ),
          currency: CurrencyCode('USD'),
          amountUsd: 30,
        ),
      ];

      final tx = Transaccion.crear(postings: postings, metadata: metadata);
      expect(tx.postings, equals(postings));
    });

    test('postings es inmodificable después de crear', () {
      final metadata = TransaccionMetadata(
        eventId: EventId('evt-125'),
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

      expect(
        () => tx.postings.add(
          Posting(
            target: CuentaTarget(AccountId('acc-2')),
            amountNative: Money(
              amount: BigInt.from(50),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: 50,
          ),
        ),
        throwsUnsupportedError,
      );
    });
  });
}
