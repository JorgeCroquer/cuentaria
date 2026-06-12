import 'package:test/test.dart';
import 'package:event_bus/event_bus.dart';
import 'package:shared_kernel/shared_kernel.dart';

import 'package:contabilidad/domain/transaccion.dart';
import 'package:contabilidad/domain/transaccion_metadata.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:contabilidad/application/registrar_transaccion.dart';
import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/application/ledger/exceptions.dart';
import 'package:contabilidad/application/ledger/factories/registrar_reverso.dart';

void main() {
  group('RegistrarReverso', () {
    late InMemoryEventStore store;
    late InMemoryLedgerProjections projections;
    late SyncEventBus eventBus;
    late InMemoryCatalogRepository catalog;
    late RegistrarTransaccion registrarTransaccion;
    late RegistrarReverso registrarReverso;

    setUp(() {
      store = InMemoryEventStore();
      projections = InMemoryLedgerProjections();
      eventBus = SyncEventBus();
      catalog = InMemoryCatalogRepository();

      final validator = ReferentialIntegrityValidator(catalog);
      registrarTransaccion = RegistrarTransaccion(
        store: store,
        projections: projections,
        eventBus: eventBus,
        validator: validator,
      );

      registrarReverso = RegistrarReverso(
        registrar: registrarTransaccion,
        store: store,
      );
    });

    test(
      'reversar una transacción simple invierte los postings exactamente',
      () async {
        // 1. Preparar una transacción original
        final cuentaId = AccountId('acc-1');
        final sobreId = EnvelopeId('env-1');

        catalog.saveAccount(
          Account(
            id: cuentaId,
            name: 'USD Account',
            nativeCurrency: CurrencyCode('USD'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );
        catalog.saveEnvelope(
          Envelope(
            id: sobreId,
            name: 'Stage',
            role: EnvelopeRole.stage,
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        final originalId = EventId('evt-orig');
        final metadataOrig = TransaccionMetadata(
          eventId: originalId,
          tipo: 'Ingreso',
          occurredAt: DomainTimestamp(DateTime.utc(2026, 6, 11)),
          recordedAt: DomainTimestamp(DateTime.utc(2026, 6, 11, 12)),
          deviceId: 'dev-1',
          schemaVersion: 1,
        );

        final postingsOrig = [
          Posting(
            target: CuentaTarget(cuentaId),
            amountNative: Money(
              amount: BigInt.from(10000),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: 10000,
          ),
          Posting(
            target: SobreTarget(sobreId),
            amountNative: Money(
              amount: BigInt.from(10000),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: 10000,
          ),
        ];

        final txOrig = Transaccion.crear(
          postings: postingsOrig,
          metadata: metadataOrig,
        );
        await registrarTransaccion(
          postings: postingsOrig,
          metadata: metadataOrig,
        );

        expect(projections.saldoCuenta(cuentaId).usd, equals(10000));
        expect(projections.saldoUsdSobre(sobreId), equals(10000));

        // 2. Reversar
        await registrarReverso(
          eventId: EventId('evt-rev'),
          deviceId: 'dev-2',
          originalEventId: originalId,
        );

        // 3. Verificar resultados
        expect(store.events.length, equals(2));
        final revTx = store.events.last;

        expect(revTx.metadata.tipo, equals('Reverso'));
        expect(revTx.metadata.reverses, equals(originalId));
        expect(revTx.postings.length, equals(2));

        // La negación es exacta
        final pC = revTx.postings.firstWhere((p) => p.target is CuentaTarget);
        final pS = revTx.postings.firstWhere((p) => p.target is SobreTarget);

        expect(pC.amountNative.amount, equals(BigInt.from(-10000)));
        expect(pC.amountUsd, equals(-10000));
        expect(pS.amountNative.amount, equals(BigInt.from(-10000)));
        expect(pS.amountUsd, equals(-10000));

        // El saldo vuelve a 0
        expect(projections.saldoCuenta(cuentaId).usd, equals(0));
        expect(projections.saldoUsdSobre(sobreId), equals(0));
      },
    );

    test(
      'reversar una realización revierte su diferencial (3 postings)',
      () async {
        final cuentaId = AccountId('acc-bs');
        final sobreGastoId = EnvelopeId('env-gasto');
        final diferencialId = catalog.getSystemEnvelope(
          EnvelopeRole.diferencial,
        );

        catalog.saveAccount(
          Account(
            id: cuentaId,
            name: 'Bs Account',
            nativeCurrency: CurrencyCode('VES'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );
        catalog.saveEnvelope(
          Envelope(
            id: sobreGastoId,
            name: 'Comida',
            role: EnvelopeRole.ninguno,
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        final originalId = EventId('evt-realizacion');
        final metadataOrig = TransaccionMetadata(
          eventId: originalId,
          tipo: 'Gasto',
          occurredAt: DomainTimestamp(DateTime.utc(2026, 6, 11)),
          recordedAt: DomainTimestamp(DateTime.utc(2026, 6, 11, 12)),
          deviceId: 'dev-1',
          schemaVersion: 1,
        );

        final postingsOrig = [
          Posting(
            target: CuentaTarget(cuentaId),
            amountNative: Money(
              amount: BigInt.from(-100000),
              currency: CurrencyCode('VES'),
            ),
            currency: CurrencyCode('VES'),
            amountUsd: -2500, // Costo base: $25.00
            rateRef: '40.0',
          ),
          Posting(
            target: SobreTarget(sobreGastoId),
            amountNative: Money(
              amount: BigInt.from(-2000),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: -2000, // Valor mercado: $20.00
            rateRef: '50.0',
          ),
          Posting(
            target: SobreTarget(diferencialId),
            amountNative: Money(
              amount: BigInt.from(-500),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: -500, // Diferencial (pérdida): -$5.00
          ),
        ];

        await registrarTransaccion(
          postings: postingsOrig,
          metadata: metadataOrig,
        );

        expect(projections.saldoCuenta(cuentaId).usd, equals(-2500));
        expect(projections.saldoUsdSobre(sobreGastoId), equals(-2000));
        expect(projections.saldoUsdSobre(diferencialId), equals(-500));

        await registrarReverso(
          eventId: EventId('evt-rev-2'),
          deviceId: 'dev-2',
          originalEventId: originalId,
        );

        expect(projections.saldoCuenta(cuentaId).usd, equals(0));
        expect(projections.saldoUsdSobre(sobreGastoId), equals(0));
        expect(projections.saldoUsdSobre(diferencialId), equals(0));
      },
    );

    test('lanza TransaccionNoEncontrada si el original no existe', () async {
      await expectLater(
        () => registrarReverso(
          eventId: EventId('evt-rev-3'),
          deviceId: 'dev-1',
          originalEventId: EventId('no-existe'),
        ),
        throwsA(isA<TransaccionNoEncontrada>()),
      );
    });

    test('lanza TransaccionYaReversada si ya fue reversada', () async {
      final cuentaId = AccountId('acc-1');
      catalog.saveAccount(
        Account(
          id: cuentaId,
          name: 'USD Account',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      final originalId = EventId('evt-orig-2');
      final metadataOrig = TransaccionMetadata(
        eventId: originalId,
        tipo: 'Ingreso',
        occurredAt: DomainTimestamp(DateTime.utc(2026, 6, 11)),
        recordedAt: DomainTimestamp(DateTime.utc(2026, 6, 11, 12)),
        deviceId: 'dev-1',
        schemaVersion: 1,
      );

      final postingsOrig = [
        Posting(
          target: CuentaTarget(cuentaId),
          amountNative: Money(
            amount: BigInt.from(100),
            currency: CurrencyCode('USD'),
          ),
          currency: CurrencyCode('USD'),
          amountUsd: 100,
        ),
        Posting(
          target: SobreTarget(catalog.getSystemEnvelope(EnvelopeRole.stage)),
          amountNative: Money(
            amount: BigInt.from(100),
            currency: CurrencyCode('USD'),
          ),
          currency: CurrencyCode('USD'),
          amountUsd: 100,
        ),
      ];

      await registrarTransaccion(
        postings: postingsOrig,
        metadata: metadataOrig,
      );

      // Primer reverso
      await registrarReverso(
        eventId: EventId('evt-rev-4'),
        deviceId: 'dev-2',
        originalEventId: originalId,
      );

      // Intento de doble reverso
      await expectLater(
        () => registrarReverso(
          eventId: EventId('evt-rev-5'),
          deviceId: 'dev-2',
          originalEventId: originalId,
        ),
        throwsA(isA<TransaccionYaReversada>()),
      );
    });
  });
}
