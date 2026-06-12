import 'package:test/test.dart';
import 'package:event_bus/event_bus.dart';
import 'package:shared_kernel/shared_kernel.dart';

import 'package:contabilidad/domain/transaccion.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:contabilidad/application/registrar_transaccion.dart';
import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/application/ledger/exceptions.dart';
import 'package:contabilidad/application/ledger/factories/registrar_transferencia.dart';

void main() {
  group('RegistrarTransferencia', () {
    late InMemoryEventStore store;
    late InMemoryLedgerProjections projections;
    late SyncEventBus eventBus;
    late InMemoryCatalogRepository catalog;
    late RegistrarTransaccion registrarTransaccion;
    late RegistrarTransferencia registrarTransferencia;

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
      
      registrarTransferencia = RegistrarTransferencia(
        registrar: registrarTransaccion,
        catalog: catalog,
      );
    });

    test('transfiere entre dos cuentas USD exitosamente', () async {
      final origenId = AccountId('acc-usd-1');
      final destinoId = AccountId('acc-usd-2');
      
      catalog.saveAccount(
        Account(
          id: origenId,
          name: 'USD Account 1',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );
      
      catalog.saveAccount(
        Account(
          id: destinoId,
          name: 'USD Account 2',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );
      
      await registrarTransferencia(
        eventId: EventId('evt-1'),
        deviceId: 'dev-1',
        cuentaOrigenId: origenId,
        cuentaDestinoId: destinoId,
        monto: Money(amount: BigInt.from(3000), currency: CurrencyCode('USD')), // 30 USD
      );
      
      expect(store.events.length, equals(1));
      final tx = store.events.first as Transaccion;
      expect(tx.metadata.tipo, equals('Transferencia'));
      
      expect(projections.saldoCuenta(origenId).usd, equals(-3000));
      expect(projections.saldoCuenta(destinoId).usd, equals(3000));
    });

    test('rechaza si es USD a EUR', () async {
      final origenId = AccountId('acc-usd-1');
      final destinoId = AccountId('acc-eur-1');
      
      catalog.saveAccount(
        Account(
          id: origenId,
          name: 'USD Account',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );
      
      catalog.saveAccount(
        Account(
          id: destinoId,
          name: 'EUR Account',
          nativeCurrency: CurrencyCode('EUR'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );
      
      await expectLater(
        () => registrarTransferencia(
          eventId: EventId('evt-2'),
          deviceId: 'dev-1',
          cuentaOrigenId: origenId,
          cuentaDestinoId: destinoId,
          monto: Money(amount: BigInt.from(3000), currency: CurrencyCode('USD')),
        ),
        throwsA(isA<TransferenciaMonedaCruzada>()),
      );
      
      expect(store.events.isEmpty, isTrue);
    });

    test('rechaza si es VES a VES (debe ser USD only)', () async {
      final origenId = AccountId('acc-ves-1');
      final destinoId = AccountId('acc-ves-2');
      
      catalog.saveAccount(
        Account(
          id: origenId,
          name: 'VES Account 1',
          nativeCurrency: CurrencyCode('VES'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );
      
      catalog.saveAccount(
        Account(
          id: destinoId,
          name: 'VES Account 2',
          nativeCurrency: CurrencyCode('VES'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );
      
      await expectLater(
        () => registrarTransferencia(
          eventId: EventId('evt-3'),
          deviceId: 'dev-1',
          cuentaOrigenId: origenId,
          cuentaDestinoId: destinoId,
          monto: Money(amount: BigInt.from(3000), currency: CurrencyCode('VES')),
        ),
        throwsA(isA<OperacionSoloUSD>()),
      );
      
      expect(store.events.isEmpty, isTrue);
    });
  });
}
