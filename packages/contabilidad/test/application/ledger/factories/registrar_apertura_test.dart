import 'package:test/test.dart';
import 'package:decimal/decimal.dart';
import 'package:event_bus/event_bus.dart';
import 'package:shared_kernel/shared_kernel.dart';

import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:contabilidad/application/registrar_transaccion.dart';
import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/application/catalog/exceptions.dart';
import 'package:contabilidad/application/ledger/factories/registrar_apertura.dart';
import 'package:contabilidad/application/ledger/factories/registrar_distribucion.dart';

void main() {
  group('RegistrarApertura', () {
    late InMemoryEventStore store;
    late InMemoryLedgerProjections projections;
    late SyncEventBus eventBus;
    late InMemoryCatalogRepository catalog;
    late RegistrarTransaccion registrarTransaccion;
    late RegistrarApertura registrarApertura;

    setUp(() {
      store = InMemoryEventStore();
      projections = InMemoryLedgerProjections();
      eventBus = SyncEventBus();
      catalog = InMemoryCatalogRepository();

      // No manual seeding of system envelopes needed, InMemoryCatalogRepository seeds them.

      final validator = ReferentialIntegrityValidator(catalog);
      registrarTransaccion = RegistrarTransaccion(
        store: store,
        projections: projections,
        eventBus: eventBus,
        validator: validator,
      );

      registrarApertura = RegistrarApertura(
        registrar: registrarTransaccion,
        catalog: catalog,
        projections: projections,
      );
    });

    test('cuenta USD usa montoNative directo', () async {
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

      await registrarApertura(
        eventId: EventId('evt-1'),
        deviceId: 'dev-1',
        cuentaId: cuentaId,
        montoNative: Money(
          amount: BigInt.from(10000),
          currency: CurrencyCode('USD'),
        ),
      );

      expect(store.events.length, equals(1));
      final tx = store.events.first;
      expect(tx.metadata.tipo, equals('Apertura'));

      final sysAperturaId = catalog.getSystemEnvelope(EnvelopeRole.apertura);

      // Projections
      expect(projections.saldoCuenta(cuentaId).usd, equals(10000));
      expect(projections.saldoUsdSobre(sysAperturaId), equals(10000));

      // Postings check
      expect(tx.postings.length, equals(2));
      final pCuenta = tx.postings.firstWhere((p) => p.target is CuentaTarget);
      final pSobre = tx.postings.firstWhere((p) => p.target is SobreTarget);

      expect(pCuenta.amountUsd, equals(10000));
      expect(pCuenta.amountNative.amount, equals(BigInt.from(10000)));

      expect(pSobre.amountUsd, equals(10000));
    });

    test('cuenta extranjera con amountUsd usa amountUsd directo', () async {
      final cuentaId = AccountId('acc-ext');
      catalog.saveAccount(
        Account(
          id: cuentaId,
          name: 'EUR Account',
          nativeCurrency: CurrencyCode('EUR'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      await registrarApertura(
        eventId: EventId('evt-2'),
        deviceId: 'dev-1',
        cuentaId: cuentaId,
        montoNative: Money(
          amount: BigInt.from(10000),
          currency: CurrencyCode('EUR'),
        ),
        amountUsd: 11000,
      );

      final sysAperturaId = catalog.getSystemEnvelope(EnvelopeRole.apertura);
      expect(projections.saldoCuenta(cuentaId).usd, equals(11000));
      expect(projections.saldoUsdSobre(sysAperturaId), equals(11000));
    });

    test(
      'cuenta extranjera con rate calcula usd con precision decimal',
      () async {
        final cuentaId = AccountId('acc-ext-2');
        catalog.saveAccount(
          Account(
            id: cuentaId,
            name: 'VES Account',
            nativeCurrency: CurrencyCode('VES'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        await registrarApertura(
          eventId: EventId('evt-3'),
          deviceId: 'dev-1',
          cuentaId: cuentaId,
          montoNative: Money(
            amount: BigInt.from(10000),
            currency: CurrencyCode('VES'),
          ),
          rate: Decimal.parse('40.0'), // 10000 / 40.0 = 250
        );

        final sysAperturaId = catalog.getSystemEnvelope(EnvelopeRole.apertura);
        expect(projections.saldoCuenta(cuentaId).usd, equals(250));
        expect(projections.saldoUsdSobre(sysAperturaId), equals(250));
      },
    );

    test(
      'rechaza cuenta no existente, falta de param extranjera, y re-apertura',
      () async {
        final cuentaId = AccountId('acc-ext-3');

        // 1. Target inexistente
        await expectLater(
          () => registrarApertura(
            eventId: EventId('evt-4'),
            deviceId: 'dev-1',
            cuentaId: cuentaId,
            montoNative: Money(
              amount: BigInt.from(100),
              currency: CurrencyCode('EUR'),
            ),
          ),
          throwsA(isA<TargetInexistente>()),
        );

        catalog.saveAccount(
          Account(
            id: cuentaId,
            name: 'EUR Account 3',
            nativeCurrency: CurrencyCode('EUR'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        // 2. Extranjera sin amountUsd ni rate
        await expectLater(
          () => registrarApertura(
            eventId: EventId('evt-5'),
            deviceId: 'dev-1',
            cuentaId: cuentaId,
            montoNative: Money(
              amount: BigInt.from(100),
              currency: CurrencyCode('EUR'),
            ),
          ),
          throwsA(isA<ArgumentError>()),
        );

        // 3. Re-apertura
        await registrarApertura(
          eventId: EventId('evt-6'),
          deviceId: 'dev-1',
          cuentaId: cuentaId,
          montoNative: Money(
            amount: BigInt.from(100),
            currency: CurrencyCode('EUR'),
          ),
          amountUsd: 110,
        );

        await expectLater(
          () => registrarApertura(
            eventId: EventId('evt-7'),
            deviceId: 'dev-1',
            cuentaId: cuentaId,
            montoNative: Money(
              amount: BigInt.from(100),
              currency: CurrencyCode('EUR'),
            ),
            amountUsd: 110,
          ),
          throwsA(isA<ArgumentError>()), // Guard trigger
        );
      },
    );
  });

  group('Apertura + Distribucion Integration', () {
    test(
      'Registra apertura y luego distribuye dejando apertura en cero',
      () async {
        final store = InMemoryEventStore();
        final projections = InMemoryLedgerProjections();
        final eventBus = SyncEventBus();
        final catalog = InMemoryCatalogRepository();

        final validator = ReferentialIntegrityValidator(catalog);
        final registrarTransaccion = RegistrarTransaccion(
          store: store,
          projections: projections,
          eventBus: eventBus,
          validator: validator,
        );

        final registrarApertura = RegistrarApertura(
          registrar: registrarTransaccion,
          catalog: catalog,
          projections: projections,
        );

        // We also need RegistrarDistribucion for integration
        // Import missing factory at the top if needed... actually we can just instantiate it
        final registrarDistribucion = RegistrarDistribucion(
          registrar: registrarTransaccion,
          catalog: catalog,
        );

        final sysAperturaId = catalog.getSystemEnvelope(EnvelopeRole.apertura);
        final cuentaId = AccountId('acc-usd-int');
        catalog.saveAccount(
          Account(
            id: cuentaId,
            name: 'USD Int',
            nativeCurrency: CurrencyCode('USD'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        final env1 = EnvelopeId('env-int-1');
        final env2 = EnvelopeId('env-int-2');
        catalog.saveEnvelope(
          Envelope(
            id: env1,
            name: 'E1',
            role: EnvelopeRole.ninguno,
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );
        catalog.saveEnvelope(
          Envelope(
            id: env2,
            name: 'E2',
            role: EnvelopeRole.ninguno,
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        // 1. Apertura
        await registrarApertura(
          eventId: EventId('evt-int-1'),
          deviceId: 'dev-1',
          cuentaId: cuentaId,
          montoNative: Money(
            amount: BigInt.from(300),
            currency: CurrencyCode('USD'),
          ),
        );

        expect(projections.saldoUsdSobre(sysAperturaId), equals(300));

        // 2. Distribucion
        final movimientos = [
          MovimientoDistribucion(sobreId: sysAperturaId, amountUsd: -300),
          MovimientoDistribucion(sobreId: env1, amountUsd: 200),
          MovimientoDistribucion(sobreId: env2, amountUsd: 100),
        ];

        await registrarDistribucion(
          eventId: EventId('evt-int-2'),
          deviceId: 'dev-1',
          movimientos: movimientos,
        );

        // 3. Validate
        expect(projections.saldoUsdSobre(sysAperturaId), equals(0));
        expect(projections.saldoUsdSobre(env1), equals(200));
        expect(projections.saldoUsdSobre(env2), equals(100));
        expect(projections.saldoCuenta(cuentaId).usd, equals(300));
      },
    );
  });
}
