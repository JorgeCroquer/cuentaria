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
import 'package:contabilidad/application/ledger/factories/registrar_gasto_usd.dart';

void main() {
  group('RegistrarGastoUsd', () {
    late InMemoryEventStore store;
    late InMemoryLedgerProjections projections;
    late SyncEventBus eventBus;
    late InMemoryCatalogRepository catalog;
    late RegistrarTransaccion registrarTransaccion;
    late RegistrarGastoUsd registrarGastoUsd;

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

      registrarGastoUsd = RegistrarGastoUsd(
        registrar: registrarTransaccion,
        catalog: catalog,
      );
    });

    test('gasto descuenta de cuenta USD y sobre', () async {
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

      final sobreId = EnvelopeId('env-1');
      catalog.saveEnvelope(
        Envelope(
          id: sobreId,
          name: 'Comida',
          role: EnvelopeRole.ninguno,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      await registrarGastoUsd(
        eventId: EventId('evt-1'),
        deviceId: 'dev-1',
        cuentaId: cuentaId,
        sobreId: sobreId,
        monto: Money(
          amount: BigInt.from(5000),
          currency: CurrencyCode('USD'),
        ), // 50 USD
      );

      expect(store.events.length, equals(1));
      final tx = store.events.first;
      expect(tx.metadata.tipo, equals('Gasto'));

      expect(projections.saldoCuenta(cuentaId).usd, equals(-5000));
      expect(projections.saldoUsdSobre(sobreId), equals(-5000));
    });

    test('gasto rechaza cuenta no USD', () async {
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

      final sobreId = EnvelopeId('env-1');
      catalog.saveEnvelope(
        Envelope(
          id: sobreId,
          name: 'Comida',
          role: EnvelopeRole.ninguno,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      await expectLater(
        () => registrarGastoUsd(
          eventId: EventId('evt-2'),
          deviceId: 'dev-1',
          cuentaId: cuentaId,
          sobreId: sobreId,
          monto: Money(amount: BigInt.from(500), currency: CurrencyCode('VES')),
        ),
        throwsA(isA<OperacionSoloUSD>()),
      );

      expect(store.events.isEmpty, isTrue);
    });

    test('gasto rechaza monto negativo o cero', () async {
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

      final sobreId = EnvelopeId('env-1');
      catalog.saveEnvelope(
        Envelope(
          id: sobreId,
          name: 'Comida',
          role: EnvelopeRole.ninguno,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      await expectLater(
        () => registrarGastoUsd(
          eventId: EventId('evt-3'),
          deviceId: 'dev-1',
          cuentaId: cuentaId,
          sobreId: sobreId,
          monto: Money(
            amount: BigInt.from(-500),
            currency: CurrencyCode('USD'),
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );

      await expectLater(
        () => registrarGastoUsd(
          eventId: EventId('evt-4'),
          deviceId: 'dev-1',
          cuentaId: cuentaId,
          sobreId: sobreId,
          monto: Money(amount: BigInt.from(0), currency: CurrencyCode('USD')),
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(store.events.isEmpty, isTrue);
    });
  });
}
