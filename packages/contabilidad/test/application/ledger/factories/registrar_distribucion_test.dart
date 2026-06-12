import 'package:test/test.dart';
import 'package:event_bus/event_bus.dart';
import 'package:shared_kernel/shared_kernel.dart';

import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:contabilidad/application/registrar_transaccion.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/application/ledger/factories/registrar_distribucion.dart';
import 'package:contabilidad/application/catalog/exceptions.dart';
import 'package:contabilidad/domain/posting_target.dart';

void main() {
  group('RegistrarDistribucion', () {
    late InMemoryEventStore store;
    late InMemoryLedgerProjections projections;
    late SyncEventBus eventBus;
    late InMemoryCatalogRepository catalog;
    late RegistrarTransaccion registrarTransaccion;
    late RegistrarDistribucion registrarDistribucion;

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
      
      registrarDistribucion = RegistrarDistribucion(
        registrar: registrarTransaccion,
        catalog: catalog,
      );
    });

    test('rechaza si la suma de montos no es exactamente 0', () async {
      final sobreId1 = EnvelopeId('env-1');
      final sobreId2 = EnvelopeId('env-2');
      
      catalog.saveEnvelope(
        Envelope(
          id: sobreId1,
          name: 'Sobre 1',
          role: EnvelopeRole.ninguno,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );
      
      catalog.saveEnvelope(
        Envelope(
          id: sobreId2,
          name: 'Sobre 2',
          role: EnvelopeRole.ninguno,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );
      
      // Suma es -100 + 50 = -50 != 0
      final movimientos = [
        MovimientoDistribucion(sobreId: sobreId1, amountUsd: -100),
        MovimientoDistribucion(sobreId: sobreId2, amountUsd: 50),
      ];

      await expectLater(
        () => registrarDistribucion(
          eventId: EventId('evt-1'),
          deviceId: 'dev-1',
          movimientos: movimientos,
        ),
        throwsA(isA<ArgumentError>()), // or specific Exception, e.g. TransaccionNoBalanceada
      );
      
      expect(store.events.isEmpty, isTrue);
    });

    test('rechaza si un sobre no existe', () async {
      final sobreId = EnvelopeId('env-real');
      final missingId = EnvelopeId('env-fake');
      
      catalog.saveEnvelope(
        Envelope(
          id: sobreId,
          name: 'Sobre Real',
          role: EnvelopeRole.ninguno,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );
      
      final movimientos = [
        MovimientoDistribucion(sobreId: sobreId, amountUsd: 100),
        MovimientoDistribucion(sobreId: missingId, amountUsd: -100),
      ];

      await expectLater(
        () => registrarDistribucion(
          eventId: EventId('evt-2'),
          deviceId: 'dev-1',
          movimientos: movimientos,
        ),
        throwsA(isA<TargetInexistente>()),
      );
      
      expect(store.events.isEmpty, isTrue);
    });

    test('genera postings con SobreTarget en USD y persiste exitosamente', () async {
      final sobreId1 = EnvelopeId('env-1');
      final sobreId2 = EnvelopeId('env-2');
      final sobreId3 = EnvelopeId('env-3');
      
      for (var id in [sobreId1, sobreId2, sobreId3]) {
        catalog.saveEnvelope(
          Envelope(
            id: id,
            name: 'Sobre ${id.value}',
            role: EnvelopeRole.ninguno,
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );
      }
      
      final movimientos = [
        MovimientoDistribucion(sobreId: sobreId1, amountUsd: -150),
        MovimientoDistribucion(sobreId: sobreId2, amountUsd: 100),
        MovimientoDistribucion(sobreId: sobreId3, amountUsd: 50),
      ];

      await registrarDistribucion(
        eventId: EventId('evt-3'),
        deviceId: 'dev-1',
        movimientos: movimientos,
      );
      
      expect(store.events.length, equals(1));
      final tx = store.events.first;
      expect(tx.metadata.tipo, equals('Distribucion'));
      
      expect(tx.postings.length, equals(3));
      
      // Verification of projections
      expect(projections.saldoUsdSobre(sobreId1), equals(-150));
      expect(projections.saldoUsdSobre(sobreId2), equals(100));
      expect(projections.saldoUsdSobre(sobreId3), equals(50));
      
      // Native amount must be USD amount, currency must be USD
      for (var posting in tx.postings) {
        expect(posting.target, isA<SobreTarget>());
        expect(posting.currency, equals(CurrencyCode('USD')));
        expect(posting.amountNative.amount, equals(BigInt.from(posting.amountUsd)));
      }
    });
  });
}
