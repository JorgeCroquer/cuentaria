import 'package:test/test.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/ledger/exceptions.dart';
import 'package:contabilidad/application/registrar_transaccion.dart';
import 'package:event_bus/event_bus.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/application/ledger/factories/registrar_conversion_adquisicion.dart';

void main() {
  group('RegistrarConversionAdquisicion', () {
    late InMemoryEventStore store;
    late InMemoryLedgerProjections projections;
    late SyncEventBus eventBus;
    late InMemoryCatalogRepository catalog;
    late RegistrarTransaccion registrar;
    late RegistrarConversionAdquisicion factory;

    setUp(() {
      store = InMemoryEventStore();
      projections = InMemoryLedgerProjections();
      eventBus = SyncEventBus();
      catalog = InMemoryCatalogRepository();

      final validator = ReferentialIntegrityValidator(catalog);
      registrar = RegistrarTransaccion(
        store: store,
        projections: projections,
        eventBus: eventBus,
        validator: validator,
      );

      factory = RegistrarConversionAdquisicion(
        registrar: registrar,
        catalog: catalog,
      );
    });

    test(
      'produce 2 postings balanceados heredando costo USD y guardando rateRef',
      () async {
        final cuentaUsdId = AccountId('acc-usd');
        final cuentaBsId = AccountId('acc-bs');

        catalog.saveAccount(
          Account(
            id: cuentaUsdId,
            name: 'USD Cash',
            nativeCurrency: CurrencyCode('USD'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        catalog.saveAccount(
          Account(
            id: cuentaBsId,
            name: 'Bs Banco',
            nativeCurrency: CurrencyCode('VES'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        await factory(
          eventId: EventId('evt-conv-1'),
          deviceId: 'dev-1',
          cuentaOrigenUsdId: cuentaUsdId,
          cuentaDestinoExtId: cuentaBsId,
          montoUsd: Money(
            amount: BigInt.from(10000),
            currency: CurrencyCode('USD'),
          ), // $100.00
          montoExtRecibido: Money(
            amount: BigInt.from(400000),
            currency: CurrencyCode('VES'),
          ), // 4000.00 Bs
          rateRef: '40.00 VES/USD',
        );

        expect(store.events.length, equals(1));
        final event = store.events.first;
        expect(event.metadata.tipo, equals('ConversionAdquisicion'));

        expect(event.postings.length, equals(2));

        final postingUsd = event.postings[0];
        expect(postingUsd.target, equals(CuentaTarget(cuentaUsdId)));
        expect(
          postingUsd.amountNative,
          equals(
            Money(amount: BigInt.from(-10000), currency: CurrencyCode('USD')),
          ),
        );
        expect(postingUsd.amountUsd, equals(-10000));
        expect(postingUsd.rateRef, isNull);

        final postingBs = event.postings[1];
        expect(postingBs.target, equals(CuentaTarget(cuentaBsId)));
        expect(
          postingBs.amountNative,
          equals(
            Money(amount: BigInt.from(400000), currency: CurrencyCode('VES')),
          ),
        );
        expect(postingBs.amountUsd, equals(10000)); // hereda costo exacto
        expect(postingBs.rateRef, equals('40.00 VES/USD'));
      },
    );

    test('rechaza si cuenta origen no es USD', () async {
      final cuentaEurId = AccountId('acc-eur');
      final cuentaBsId = AccountId('acc-bs');

      catalog.saveAccount(
        Account(
          id: cuentaEurId,
          name: 'EUR',
          nativeCurrency: CurrencyCode('EUR'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );
      catalog.saveAccount(
        Account(
          id: cuentaBsId,
          name: 'Bs',
          nativeCurrency: CurrencyCode('VES'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      await expectLater(
        () => factory(
          eventId: EventId('evt-conv-2'),
          deviceId: 'dev-1',
          cuentaOrigenUsdId: cuentaEurId,
          cuentaDestinoExtId: cuentaBsId,
          montoUsd: Money(
            amount: BigInt.from(100),
            currency: CurrencyCode('USD'),
          ),
          montoExtRecibido: Money(
            amount: BigInt.from(4000),
            currency: CurrencyCode('VES'),
          ),
          rateRef: '40',
        ),
        throwsA(isA<OperacionSoloUSD>()),
      );
    });

    test('rechaza si cuenta destino es USD', () async {
      final cuentaUsdId = AccountId('acc-usd');
      final cuentaUsd2Id = AccountId('acc-usd2');

      catalog.saveAccount(
        Account(
          id: cuentaUsdId,
          name: 'USD 1',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );
      catalog.saveAccount(
        Account(
          id: cuentaUsd2Id,
          name: 'USD 2',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      await expectLater(
        () => factory(
          eventId: EventId('evt-conv-3'),
          deviceId: 'dev-1',
          cuentaOrigenUsdId: cuentaUsdId,
          cuentaDestinoExtId: cuentaUsd2Id,
          montoUsd: Money(
            amount: BigInt.from(100),
            currency: CurrencyCode('USD'),
          ),
          montoExtRecibido: Money(
            amount: BigInt.from(100),
            currency: CurrencyCode('USD'),
          ),
          rateRef: '1',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'msg',
            contains('La cuenta destino no puede ser USD'),
          ),
        ),
      );
    });

    test('rechaza montos negativos o cero', () async {
      final cuentaUsdId = AccountId('acc-usd');
      final cuentaBsId = AccountId('acc-bs');

      catalog.saveAccount(
        Account(
          id: cuentaUsdId,
          name: 'USD',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );
      catalog.saveAccount(
        Account(
          id: cuentaBsId,
          name: 'Bs',
          nativeCurrency: CurrencyCode('VES'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      // usd cero
      await expectLater(
        () => factory(
          eventId: EventId('evt-conv-4'),
          deviceId: 'dev-1',
          cuentaOrigenUsdId: cuentaUsdId,
          cuentaDestinoExtId: cuentaBsId,
          montoUsd: Money(
            amount: BigInt.from(0),
            currency: CurrencyCode('USD'),
          ),
          montoExtRecibido: Money(
            amount: BigInt.from(4000),
            currency: CurrencyCode('VES'),
          ),
          rateRef: '40',
        ),
        throwsA(isA<ArgumentError>()),
      );

      // bs cero
      await expectLater(
        () => factory(
          eventId: EventId('evt-conv-5'),
          deviceId: 'dev-1',
          cuentaOrigenUsdId: cuentaUsdId,
          cuentaDestinoExtId: cuentaBsId,
          montoUsd: Money(
            amount: BigInt.from(100),
            currency: CurrencyCode('USD'),
          ),
          montoExtRecibido: Money(
            amount: BigInt.from(0),
            currency: CurrencyCode('VES'),
          ),
          rateRef: '40',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
