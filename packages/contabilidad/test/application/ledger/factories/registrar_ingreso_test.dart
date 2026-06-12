import 'package:test/test.dart';
import 'package:event_bus/event_bus.dart';
import 'package:shared_kernel/shared_kernel.dart';

import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:contabilidad/application/registrar_transaccion.dart';
import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/application/ledger/exceptions.dart';
import 'package:contabilidad/application/ledger/factories/registrar_ingreso.dart';

void main() {
  group('RegistrarIngreso', () {
    late InMemoryEventStore store;
    late InMemoryLedgerProjections projections;
    late SyncEventBus eventBus;
    late InMemoryCatalogRepository catalog;
    late RegistrarTransaccion registrarTransaccion;
    late RegistrarIngreso registrarIngreso;

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

      registrarIngreso = RegistrarIngreso(
        registrar: registrarTransaccion,
        catalog: catalog,
      );
    });

    test('ingreso a cuenta USD con sobre Stage implícito', () async {
      final cuentaId = AccountId('acc-usd');
      catalog.saveAccount(
        Account(
          id: cuentaId,
          name: 'USD Account',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      final stageId = catalog.getSystemEnvelope(EnvelopeRole.stage);

      await registrarIngreso(
        eventId: EventId('evt-1'),
        deviceId: 'dev-1',
        cuentaId: cuentaId,
        monto: Money(
          amount: BigInt.from(15000),
          currency: CurrencyCode('USD'),
        ), // 150 USD
        source: 'Cliente A',
      );

      expect(store.events.length, equals(1));
      final tx = store.events.first;
      expect(tx.metadata.tipo, equals('Ingreso'));
      expect(tx.metadata.source, equals('Cliente A'));

      expect(projections.saldoCuenta(cuentaId).usd, equals(15000));
      expect(projections.saldoUsdSobre(stageId), equals(15000));
    });

    test('ingreso a cuenta USD con sobre explícito', () async {
      final cuentaId = AccountId('acc-usd');
      catalog.saveAccount(
        Account(
          id: cuentaId,
          name: 'USD Account',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      final sobreDestinoId = EnvelopeId('env-viaje');
      catalog.saveEnvelope(
        Envelope(
          id: sobreDestinoId,
          name: 'Viaje',
          role: EnvelopeRole.ninguno,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      await registrarIngreso(
        eventId: EventId('evt-1'),
        deviceId: 'dev-1',
        cuentaId: cuentaId,
        sobreId: sobreDestinoId,
        monto: Money(
          amount: BigInt.from(15000),
          currency: CurrencyCode('USD'),
        ), // 150 USD
        source: 'Cliente A',
      );

      expect(projections.saldoCuenta(cuentaId).usd, equals(15000));
      expect(projections.saldoUsdSobre(sobreDestinoId), equals(15000));
    });

    test('ingreso rechaza cuenta no USD', () async {
      final cuentaId = AccountId('acc-ves');
      catalog.saveAccount(
        Account(
          id: cuentaId,
          name: 'VES Account',
          nativeCurrency: CurrencyCode('VES'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      await expectLater(
        () => registrarIngreso(
          eventId: EventId('evt-2'),
          deviceId: 'dev-1',
          cuentaId: cuentaId,
          monto: Money(amount: BigInt.from(500), currency: CurrencyCode('VES')),
          source: 'Cliente B',
        ),
        throwsA(isA<OperacionSoloUSD>()),
      );

      expect(store.events.isEmpty, isTrue);
    });

    test('ingreso rechaza monto negativo o cero', () async {
      final cuentaId = AccountId('acc-usd');
      catalog.saveAccount(
        Account(
          id: cuentaId,
          name: 'USD Account',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      await expectLater(
        () => registrarIngreso(
          eventId: EventId('evt-3'),
          deviceId: 'dev-1',
          cuentaId: cuentaId,
          monto: Money(
            amount: BigInt.from(-15000),
            currency: CurrencyCode('USD'),
          ),
          source: 'Cliente C',
        ),
        throwsA(isA<ArgumentError>()),
      );

      await expectLater(
        () => registrarIngreso(
          eventId: EventId('evt-4'),
          deviceId: 'dev-1',
          cuentaId: cuentaId,
          monto: Money(amount: BigInt.from(0), currency: CurrencyCode('USD')),
          source: 'Cliente D',
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(store.events.isEmpty, isTrue);
    });
  });
}
