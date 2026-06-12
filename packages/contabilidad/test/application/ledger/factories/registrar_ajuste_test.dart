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
import 'package:contabilidad/application/ledger/factories/registrar_ajuste.dart';

void main() {
  group('RegistrarAjuste', () {
    late InMemoryEventStore store;
    late InMemoryLedgerProjections projections;
    late SyncEventBus eventBus;
    late InMemoryCatalogRepository catalog;
    late RegistrarTransaccion registrarTransaccion;
    late RegistrarAjuste registrarAjuste;

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

      registrarAjuste = RegistrarAjuste(
        registrar: registrarTransaccion,
        projections: projections,
        catalog: catalog,
      );
    });

    // 5. Ajustar incrementa saldo de cuenta USD
    test(
      'incrementar saldo de cuenta USD postea con signo positivo en Cuenta y Ajustes',
      () async {
        final cuentaId = AccountId('acc-usd');
        final ajustesId = catalog.getSystemEnvelope(EnvelopeRole.ajustes);

        catalog.saveAccount(
          Account(
            id: cuentaId,
            name: 'USD Account',
            nativeCurrency: CurrencyCode('USD'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        // Saldo inicial 0
        expect(projections.saldoCuenta(cuentaId).usd, equals(0));

        await registrarAjuste(
          eventId: EventId('evt-ajuste-1'),
          deviceId: 'dev-1',
          cuentaId: cuentaId,
          saldoRealNative: Money(
            amount: BigInt.from(5000),
            currency: CurrencyCode('USD'),
          ), // +$50.00
        );

        expect(store.events.length, equals(1));
        final tx = store.events.first;
        expect(tx.metadata.tipo, equals('Ajuste'));

        final pC = tx.postings.firstWhere((p) => p.target is CuentaTarget);
        final pS = tx.postings.firstWhere((p) => p.target is SobreTarget);

        expect(pC.amountNative.amount, equals(BigInt.from(5000)));
        expect(pC.amountUsd, equals(5000));
        expect(pS.amountNative.amount, equals(BigInt.from(5000)));
        expect(pS.amountUsd, equals(5000));
        expect((pS.target as SobreTarget).envelopeId, equals(ajustesId));

        expect(projections.saldoCuenta(cuentaId).usd, equals(5000));
        expect(projections.saldoUsdSobre(ajustesId), equals(5000));
      },
    );

    // 6. Ajustar rechaza incremento de cuenta extranjera
    test(
      'lanza AjustePositivoMonedaExtranjeraNoPermitido si delta es positivo en cuenta no-USD',
      () async {
        final cuentaId = AccountId('acc-ves');
        catalog.saveAccount(
          Account(
            id: cuentaId,
            name: 'Bs Account',
            nativeCurrency: CurrencyCode('VES'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        await expectLater(
          () => registrarAjuste(
            eventId: EventId('evt-ajuste-2'),
            deviceId: 'dev-1',
            cuentaId: cuentaId,
            saldoRealNative: Money(
              amount: BigInt.from(100),
              currency: CurrencyCode('VES'),
            ), // Positivo
          ),
          throwsA(isA<AjustePositivoMonedaExtranjeraNoPermitido>()),
        );
      },
    );

    // 7. Ajustar decrementa saldo
    test('decrementar saldo usa costo base y signos negativos', () async {
      final cuentaId = AccountId('acc-ves');
      final ajustesId = catalog.getSystemEnvelope(EnvelopeRole.ajustes);

      catalog.saveAccount(
        Account(
          id: cuentaId,
          name: 'Bs Account',
          nativeCurrency: CurrencyCode('VES'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      // Inyectar saldo manualmente vía registrarTransaccion (equivalente a un Ingreso/Conversión)
      final metadataOrig = TransaccionMetadata(
        eventId: EventId('evt-orig'),
        tipo: 'Ingreso',
        occurredAt: DomainTimestamp(DateTime.now().toUtc()),
        recordedAt: DomainTimestamp(DateTime.now().toUtc()),
        deviceId: 'dev-1',
        schemaVersion: 1,
      );

      final postingsOrig = [
        Posting(
          target: CuentaTarget(cuentaId),
          amountNative: Money(
            amount: BigInt.from(1000),
            currency: CurrencyCode('VES'),
          ),
          currency: CurrencyCode('VES'),
          amountUsd: 5000, // Costo base: $50.00
        ),
        Posting(
          target: SobreTarget(catalog.getSystemEnvelope(EnvelopeRole.stage)),
          amountNative: Money(
            amount: BigInt.from(5000),
            currency: CurrencyCode('USD'),
          ),
          currency: CurrencyCode('USD'),
          amountUsd: 5000,
        ),
      ];

      await registrarTransaccion(
        postings: postingsOrig,
        metadata: metadataOrig,
      );

      expect(
        projections.saldoCuenta(cuentaId).native.amount,
        equals(BigInt.from(1000)),
      );
      expect(projections.saldoCuenta(cuentaId).usd, equals(5000));

      // Ajuste: el saldo real es 800 VES. Delta = -200 VES.
      await registrarAjuste(
        eventId: EventId('evt-ajuste-3'),
        deviceId: 'dev-1',
        cuentaId: cuentaId,
        saldoRealNative: Money(
          amount: BigInt.from(800),
          currency: CurrencyCode('VES'),
        ),
      );

      final tx = store.events.last;

      final pC = tx.postings.firstWhere((p) => p.target is CuentaTarget);
      final pS = tx.postings.firstWhere((p) => p.target is SobreTarget);

      expect(pC.amountNative.amount, equals(BigInt.from(-200)));
      // Costo base promedio: 5000 USD / 1000 VES = 5.
      // -200 VES * 5 = -1000 USD.
      expect(pC.amountUsd, equals(-1000));

      expect(pS.amountNative.amount, equals(BigInt.from(-1000)));
      expect(pS.amountUsd, equals(-1000));

      expect(
        projections.saldoCuenta(cuentaId).native.amount,
        equals(BigInt.from(800)),
      );
      expect(projections.saldoCuenta(cuentaId).usd, equals(4000));
    });

    // 8. Ajustar rechaza si no hay diferencia
    test('lanza AjusteSinDiferencia si el delta es 0', () async {
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
        () => registrarAjuste(
          eventId: EventId('evt-ajuste-4'),
          deviceId: 'dev-1',
          cuentaId: cuentaId,
          saldoRealNative: Money(
            amount: BigInt.zero,
            currency: CurrencyCode('USD'),
          ),
        ),
        throwsA(isA<AjusteSinDiferencia>()),
      );
    });
  });
}
