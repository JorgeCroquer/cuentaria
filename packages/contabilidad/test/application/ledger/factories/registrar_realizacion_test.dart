import 'dart:math' as math;
import 'package:test/test.dart';
import 'package:decimal/decimal.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:contabilidad/domain/transaccion.dart';
import 'package:contabilidad/domain/transaccion_metadata.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/ledger/exceptions.dart';
import 'package:contabilidad/application/catalog/exceptions.dart';
import 'package:contabilidad/application/registrar_transaccion.dart';
import 'package:event_bus/event_bus.dart';
import 'package:contabilidad/infrastructure/in_memory_ledger_projections.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/infrastructure/in_memory_event_store.dart';
import 'package:contabilidad/application/ledger/factories/registrar_realizacion.dart';

void main() {
  group('RegistrarRealizacion', () {
    late InMemoryEventStore store;
    late InMemoryLedgerProjections projections;
    late SyncEventBus eventBus;
    late InMemoryCatalogRepository catalog;
    late RegistrarTransaccion registrar;
    late RegistrarRealizacion factory;

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

      factory = RegistrarRealizacion(
        registrar: registrar,
        catalog: catalog,
        projections: projections,
      );
    });

    test(
      'Overdraw Rejection: lanza SaldoInsuficiente si montoNative > saldo.native',
      () async {
        final cuentaBsId = AccountId('acc-bs');
        final sobreDestinoId = EnvelopeId('env-destino');

        catalog.saveAccount(
          Account(
            id: cuentaBsId,
            name: 'Bs Banco',
            nativeCurrency: CurrencyCode('VES'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        catalog.saveEnvelope(
          Envelope(
            id: sobreDestinoId,
            name: 'Gastos',
            role: EnvelopeRole.ninguno,
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        // Add 100 VES balance via a direct event to projections
        final initialEvent = Transaccion.crear(
          metadata: TransaccionMetadata(
            eventId: EventId('evt-init'),
            tipo: 'Apertura',
            occurredAt: DomainTimestamp(DateTime.now().toUtc()),
            recordedAt: DomainTimestamp(DateTime.now().toUtc()),
            deviceId: 'dev',
            schemaVersion: 1,
          ),
          postings: [
            Posting(
              target: CuentaTarget(cuentaBsId),
              amountNative: Money(
                amount: BigInt.from(10000),
                currency: CurrencyCode('VES'),
              ), // 100 VES
              currency: CurrencyCode('VES'),
              amountUsd: 250, // $2.50
            ),
            Posting(
              target: SobreTarget(EnvelopeId('env-apertura')),
              amountNative: Money(
                amount: BigInt.from(250),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: 250,
            ),
          ],
        );
        projections.aplicar(initialEvent);

        await expectLater(
          () => factory.gastoMonedaExtranjera(
            eventId: EventId('evt-gasto-1'),
            deviceId: 'dev-1',
            cuentaId: cuentaBsId,
            sobreDestinoId: sobreDestinoId,
            montoNative: Money(
              amount: BigInt.from(15000),
              currency: CurrencyCode('VES'),
            ), // 150 VES > 100 VES
            tasaActual: Decimal.parse('40.00'), // VES/USD
          ),
          throwsA(isA<SaldoInsuficiente>()),
        );
      },
    );

    test(
      'MonedaIncompatible: gastoMonedaExtranjera rechaza cuenta USD',
      () async {
        final cuentaUsdId = AccountId('acc-usd-incompat');
        final sobreDestinoId = EnvelopeId('env-incompat');
        catalog.saveAccount(
          Account(
            id: cuentaUsdId,
            name: 'USD acc',
            nativeCurrency: CurrencyCode('USD'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );
        catalog.saveEnvelope(
          Envelope(
            id: sobreDestinoId,
            name: 'Gastos',
            role: EnvelopeRole.ninguno,
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        await expectLater(
          () => factory.gastoMonedaExtranjera(
            eventId: EventId('evt-incompat-1'),
            deviceId: 'dev',
            cuentaId: cuentaUsdId,
            sobreDestinoId: sobreDestinoId,
            montoNative: Money(
              amount: BigInt.from(100),
              currency: CurrencyCode('USD'),
            ),
            tasaActual: Decimal.parse('1.00'),
          ),
          throwsA(isA<MonedaIncompatible>()),
        );
      },
    );

    test(
      'MonedaIncompatible: conversionDisposicion rechaza cuenta origen USD',
      () async {
        final cuentaUsdId = AccountId('acc-usd-origin');
        final cuentaDestinoId = AccountId('acc-usd-dest');
        catalog.saveAccount(
          Account(
            id: cuentaUsdId,
            name: 'USD origin',
            nativeCurrency: CurrencyCode('USD'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );
        catalog.saveAccount(
          Account(
            id: cuentaDestinoId,
            name: 'USD dest',
            nativeCurrency: CurrencyCode('USD'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        await expectLater(
          () => factory.conversionDisposicion(
            eventId: EventId('evt-incompat-2'),
            deviceId: 'dev',
            cuentaOrigenExtId: cuentaUsdId,
            cuentaDestinoUsdId: cuentaDestinoId,
            montoNative: Money(
              amount: BigInt.from(100),
              currency: CurrencyCode('USD'),
            ),
            montoUsdRecibido: Money(
              amount: BigInt.from(100),
              currency: CurrencyCode('USD'),
            ),
            rateRef: '1.00 USD/USD',
          ),
          throwsA(isA<MonedaIncompatible>()),
        );
      },
    );

    test('Gasto Moneda Extranjera: genera 3 postings (Pérdida)', () async {
      final cuentaBsId = AccountId('acc-bs-2');
      final sobreDestinoId = EnvelopeId('env-destino-2');

      catalog.saveAccount(
        Account(
          id: cuentaBsId,
          name: 'Bs Banco 2',
          nativeCurrency: CurrencyCode('VES'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      catalog.saveEnvelope(
        Envelope(
          id: sobreDestinoId,
          name: 'Gastos 2',
          role: EnvelopeRole.ninguno,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      final sobreDiferencialId = catalog.getSystemEnvelope(
        EnvelopeRole.diferencial,
      );

      // Add 100 VES balance with a base cost of $5.00 (avg 20 VES/USD)
      final initialEvent = Transaccion.crear(
        metadata: TransaccionMetadata(
          eventId: EventId('evt-init-2'),
          tipo: 'Apertura',
          occurredAt: DomainTimestamp(DateTime.now().toUtc()),
          recordedAt: DomainTimestamp(DateTime.now().toUtc()),
          deviceId: 'dev',
          schemaVersion: 1,
        ),
        postings: [
          Posting(
            target: CuentaTarget(cuentaBsId),
            amountNative: Money(
              amount: BigInt.from(10000),
              currency: CurrencyCode('VES'),
            ), // 100 VES
            currency: CurrencyCode('VES'),
            amountUsd: 500, // $5.00
          ),
          Posting(
            target: SobreTarget(EnvelopeId('env-apertura')),
            amountNative: Money(
              amount: BigInt.from(500),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: 500,
          ),
        ],
      );
      projections.aplicar(initialEvent);

      // Spend 50 VES at current rate of 40 VES/USD.
      // Market value (valor_mercado) = 50 VES / 40 = $1.25 (125 cents).
      // Base cost (costo_base) = 50% of 500 cents = $2.50 (250 cents).
      // Diferencial = valor_mercado - costo_base = 125 - 250 = -125 cents (Loss).

      await factory.gastoMonedaExtranjera(
        eventId: EventId('evt-gasto-2'),
        deviceId: 'dev-2',
        cuentaId: cuentaBsId,
        sobreDestinoId: sobreDestinoId,
        montoNative: Money(
          amount: BigInt.from(5000),
          currency: CurrencyCode('VES'),
        ), // 50 VES
        tasaActual: Decimal.parse('40.00'), // VES/USD
      );

      final events = store.events;
      final event = events.last;
      expect(event.metadata.tipo, 'GastoMonedaExtranjera');
      expect(event.postings.length, 3);

      final pCuenta = event.postings.firstWhere(
        (p) => p.target == CuentaTarget(cuentaBsId),
      );
      expect(pCuenta.amountNative.amount, BigInt.from(-5000));
      expect(pCuenta.amountUsd, -250);

      final pDestino = event.postings.firstWhere(
        (p) => p.target == SobreTarget(sobreDestinoId),
      );
      expect(pDestino.amountUsd, -125);
      expect(pDestino.rateRef, '40.00 VES/USD'); // rate_ref must be stored

      final pDiferencial = event.postings.firstWhere(
        (p) => p.target == SobreTarget(sobreDiferencialId),
      );
      expect(pDiferencial.amountUsd, -125);
    });

    test('Gasto Moneda Extranjera: genera 3 postings (Ganancia)', () async {
      final cuentaBsId = AccountId('acc-bs-3');
      final sobreDestinoId = EnvelopeId('env-destino-3');
      final sobreDiferencialId = catalog.getSystemEnvelope(
        EnvelopeRole.diferencial,
      );

      catalog.saveAccount(
        Account(
          id: cuentaBsId,
          name: 'Bs 3',
          nativeCurrency: CurrencyCode('VES'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );
      catalog.saveEnvelope(
        Envelope(
          id: sobreDestinoId,
          name: 'Gastos 3',
          role: EnvelopeRole.ninguno,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      final initialEvent = Transaccion.crear(
        metadata: TransaccionMetadata(
          eventId: EventId('evt-init-3'),
          tipo: 'Apertura',
          occurredAt: DomainTimestamp(DateTime.now().toUtc()),
          recordedAt: DomainTimestamp(DateTime.now().toUtc()),
          deviceId: 'dev',
          schemaVersion: 1,
        ),
        postings: [
          Posting(
            target: CuentaTarget(cuentaBsId),
            amountNative: Money(
              amount: BigInt.from(10000),
              currency: CurrencyCode('VES'),
            ),
            currency: CurrencyCode('VES'),
            amountUsd: 200,
          ), // Base cost $2.00
          Posting(
            target: SobreTarget(EnvelopeId('env-apertura')),
            amountNative: Money(
              amount: BigInt.from(200),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: 200,
          ),
        ],
      );
      projections.aplicar(initialEvent);

      // Spend 50 VES at current rate of 25 VES/USD.
      // Market value = 50 / 25 = $2.00 (200 cents).
      // Base cost = 50% of 200 cents = $1.00 (100 cents).
      // Diferencial = 200 - 100 = +100 cents (Gain).

      await factory.gastoMonedaExtranjera(
        eventId: EventId('evt-gasto-3'),
        deviceId: 'dev-3',
        cuentaId: cuentaBsId,
        sobreDestinoId: sobreDestinoId,
        montoNative: Money(
          amount: BigInt.from(5000),
          currency: CurrencyCode('VES'),
        ), // 50 VES
        tasaActual: Decimal.parse('25.00'), // VES/USD
      );

      final event = store.events.last;

      final pCuenta = event.postings.firstWhere(
        (p) => p.target == CuentaTarget(cuentaBsId),
      );
      expect(pCuenta.amountUsd, -100);

      final pDestino = event.postings.firstWhere(
        (p) => p.target == SobreTarget(sobreDestinoId),
      );
      expect(pDestino.amountUsd, -200);

      final pDiferencial = event.postings.firstWhere(
        (p) => p.target == SobreTarget(sobreDiferencialId),
      );
      expect(pDiferencial.amountUsd, 100);
    });

    test('Conversion Disposición: usa montoUsdRecibido observado', () async {
      final cuentaBsId = AccountId('acc-bs-4');
      final cuentaUsdId = AccountId('acc-usd-4');
      final sobreDiferencialId = catalog.getSystemEnvelope(
        EnvelopeRole.diferencial,
      );

      catalog.saveAccount(
        Account(
          id: cuentaBsId,
          name: 'Bs 4',
          nativeCurrency: CurrencyCode('VES'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );
      catalog.saveAccount(
        Account(
          id: cuentaUsdId,
          name: 'USD 4',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      final initialEvent = Transaccion.crear(
        metadata: TransaccionMetadata(
          eventId: EventId('evt-init-4'),
          tipo: 'Apertura',
          occurredAt: DomainTimestamp(DateTime.now().toUtc()),
          recordedAt: DomainTimestamp(DateTime.now().toUtc()),
          deviceId: 'dev',
          schemaVersion: 1,
        ),
        postings: [
          Posting(
            target: CuentaTarget(cuentaBsId),
            amountNative: Money(
              amount: BigInt.from(10000),
              currency: CurrencyCode('VES'),
            ),
            currency: CurrencyCode('VES'),
            amountUsd: 500,
          ),
          Posting(
            target: SobreTarget(EnvelopeId('env-apertura')),
            amountNative: Money(
              amount: BigInt.from(500),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: 500,
          ),
        ],
      );
      projections.aplicar(initialEvent);

      await factory.conversionDisposicion(
        eventId: EventId('evt-conv-1'),
        deviceId: 'dev-4',
        cuentaOrigenExtId: cuentaBsId,
        cuentaDestinoUsdId: cuentaUsdId,
        montoNative: Money(
          amount: BigInt.from(5000),
          currency: CurrencyCode('VES'),
        ), // 50 VES
        montoUsdRecibido: Money(
          amount: BigInt.from(300),
          currency: CurrencyCode('USD'),
        ), // $3.00
        rateRef: '16.66 VES/USD',
      );

      final event = store.events.last;
      expect(event.metadata.tipo, 'ConversionDisposicion');
      expect(event.postings.length, 3);

      final pCuentaExt = event.postings.firstWhere(
        (p) => p.target == CuentaTarget(cuentaBsId),
      );
      expect(pCuentaExt.amountUsd, -250); // 50% de 500 = 250

      final pCuentaUsd = event.postings.firstWhere(
        (p) => p.target == CuentaTarget(cuentaUsdId),
      );
      expect(pCuentaUsd.amountUsd, 300);
      expect(pCuentaUsd.rateRef, '16.66 VES/USD');

      final pDiferencial = event.postings.firstWhere(
        (p) => p.target == SobreTarget(sobreDiferencialId),
      );
      expect(pDiferencial.amountUsd, 50); // 300 - 250 = 50
    });

    test(
      'Zero-Native: Vaciar la cuenta barre todo el costo USD restante',
      () async {
        final cuentaBsId = AccountId('acc-bs-zero');
        final sobreDestinoId = EnvelopeId('env-destino-zero');

        catalog.saveAccount(
          Account(
            id: cuentaBsId,
            name: 'Bs Zero',
            nativeCurrency: CurrencyCode('VES'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );
        catalog.saveEnvelope(
          Envelope(
            id: sobreDestinoId,
            name: 'Destino Zero',
            role: EnvelopeRole.ninguno,
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        // Initial: 30 VES with 101 cents base cost ($1.01)
        final initialEvent = Transaccion.crear(
          metadata: TransaccionMetadata(
            eventId: EventId('evt-z-init'),
            tipo: 'Apertura',
            occurredAt: DomainTimestamp(DateTime.now().toUtc()),
            recordedAt: DomainTimestamp(DateTime.now().toUtc()),
            deviceId: 'dev',
            schemaVersion: 1,
          ),
          postings: [
            Posting(
              target: CuentaTarget(cuentaBsId),
              amountNative: Money(
                amount: BigInt.from(3000),
                currency: CurrencyCode('VES'),
              ),
              currency: CurrencyCode('VES'),
              amountUsd: 101,
            ),
            Posting(
              target: SobreTarget(EnvelopeId('env-apertura')),
              amountNative: Money(
                amount: BigInt.from(101),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: 101,
            ),
          ],
        );
        projections.aplicar(initialEvent);

        // Spend 20 VES.
        // costo_base = (2000 * 101) ~/ 3000 = 67
        await factory.gastoMonedaExtranjera(
          eventId: EventId('evt-z-1'),
          deviceId: 'dev-z',
          cuentaId: cuentaBsId,
          sobreDestinoId: sobreDestinoId,
          montoNative: Money(
            amount: BigInt.from(2000),
            currency: CurrencyCode('VES'),
          ),
          tasaActual: Decimal.parse('40.00'),
        );

        final event1 = store.events.last;

        final pCuenta1 = event1.postings.firstWhere(
          (p) => p.target == CuentaTarget(cuentaBsId),
        );
        expect(pCuenta1.amountUsd, -67);

        // Spend remaining 10 VES.
        // Proporcional = (1000 * 101) ~/ 3000 = 33
        // But remaining cost is 101 - 67 = 34.
        await factory.gastoMonedaExtranjera(
          eventId: EventId('evt-z-2'),
          deviceId: 'dev-z',
          cuentaId: cuentaBsId,
          sobreDestinoId: sobreDestinoId,
          montoNative: Money(
            amount: BigInt.from(1000),
            currency: CurrencyCode('VES'),
          ),
          tasaActual: Decimal.parse('40.00'),
        );

        final event2 = store.events.last;
        final pCuenta2 = event2.postings.firstWhere(
          (p) => p.target == CuentaTarget(cuentaBsId),
        );
        expect(pCuenta2.amountUsd, -34); // Sweeps exactly 34

        final finalSaldo = projections.saldoCuenta(cuentaBsId);
        expect(finalSaldo.native.amount, BigInt.zero);
        expect(finalSaldo.usd, 0);
      },
    );

    test('Zero-Native: Test de Propiedad con operaciones aleatorias', () async {
      final cuentaBsId = AccountId('acc-bs-prop');
      final sobreDestinoId = EnvelopeId('env-destino-prop');

      catalog.saveAccount(
        Account(
          id: cuentaBsId,
          name: 'Bs Prop',
          nativeCurrency: CurrencyCode('VES'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );
      catalog.saveEnvelope(
        Envelope(
          id: sobreDestinoId,
          name: 'Destino Prop',
          role: EnvelopeRole.ninguno,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      // Initial: 10,000 VES with 33,333 cents base cost ($333.33)
      final initialNative = BigInt.from(10000);
      final initialUsd = 33333;

      final initialEvent = Transaccion.crear(
        metadata: TransaccionMetadata(
          eventId: EventId('evt-p-init'),
          tipo: 'Apertura',
          occurredAt: DomainTimestamp(DateTime.now().toUtc()),
          recordedAt: DomainTimestamp(DateTime.now().toUtc()),
          deviceId: 'dev',
          schemaVersion: 1,
        ),
        postings: [
          Posting(
            target: CuentaTarget(cuentaBsId),
            amountNative: Money(
              amount: initialNative,
              currency: CurrencyCode('VES'),
            ),
            currency: CurrencyCode('VES'),
            amountUsd: initialUsd,
          ),
          Posting(
            target: SobreTarget(EnvelopeId('env-apertura')),
            amountNative: Money(
              amount: BigInt.from(initialUsd),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: initialUsd,
          ),
        ],
      );
      projections.aplicar(initialEvent);

      BigInt remainingNative = initialNative;
      int totalUsdWithdrawn = 0;
      final random = math.Random(42);

      int op = 0;
      while (remainingNative > BigInt.zero) {
        op++;
        BigInt spend = BigInt.from(random.nextInt(remainingNative.toInt()) + 1);
        if (spend > remainingNative) spend = remainingNative;

        await factory.gastoMonedaExtranjera(
          eventId: EventId('evt-p-$op'),
          deviceId: 'dev-p',
          cuentaId: cuentaBsId,
          sobreDestinoId: sobreDestinoId,
          montoNative: Money(amount: spend, currency: CurrencyCode('VES')),
          tasaActual: Decimal.parse('40.00'),
        );

        final event = store.events.last;
        final pCuenta = event.postings.firstWhere(
          (p) => p.target == CuentaTarget(cuentaBsId),
        );
        totalUsdWithdrawn += pCuenta.amountUsd.abs();

        remainingNative -= spend;
      }

      expect(remainingNative, BigInt.zero);
      expect(totalUsdWithdrawn, initialUsd);

      final finalSaldo = projections.saldoCuenta(cuentaBsId);
      expect(finalSaldo.native.amount, BigInt.zero);
      expect(finalSaldo.usd, 0);
    });

    // --- ventaCripto ---

    test(
      'Venta Cripto: genera 3 postings (Pérdida — BTC baja de precio)',
      () async {
        // BTC account: 1 BTC acquired at $50,000 (5_000_000 cents)
        // Current price: $40,000 → realiza pérdida de $10,000
        final cuentaBtcId = AccountId('acc-btc-1');
        final cuentaDestinoUsdId = AccountId('acc-usd-btc-1');
        final sobreDiferencialId = catalog.getSystemEnvelope(
          EnvelopeRole.diferencial,
        );

        catalog.saveAccount(
          Account(
            id: cuentaBtcId,
            name: 'BTC',
            nativeCurrency: CurrencyCode('BTC'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );
        catalog.saveAccount(
          Account(
            id: cuentaDestinoUsdId,
            name: 'USD dest',
            nativeCurrency: CurrencyCode('USD'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        // 1 BTC = 100_000_000 satoshis, costo_base = $50,000 (5_000_000 cents)
        final initialEvent = Transaccion.crear(
          metadata: TransaccionMetadata(
            eventId: EventId('evt-btc-init'),
            tipo: 'Apertura',
            occurredAt: DomainTimestamp(DateTime.now().toUtc()),
            recordedAt: DomainTimestamp(DateTime.now().toUtc()),
            deviceId: 'dev',
            schemaVersion: 1,
          ),
          postings: [
            Posting(
              target: CuentaTarget(cuentaBtcId),
              amountNative: Money(
                amount: BigInt.from(100000000),
                currency: CurrencyCode('BTC'),
              ),
              currency: CurrencyCode('BTC'),
              amountUsd: 5000000,
            ),
            Posting(
              target: SobreTarget(EnvelopeId('env-apertura')),
              amountNative: Money(
                amount: BigInt.from(5000000),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: 5000000,
            ),
          ],
        );
        projections.aplicar(initialEvent);

        // Sell all 1 BTC at current price $40,000 (4_000_000 cents)
        // costo_base = 5_000_000 cents
        // precio_actual = $40,000 → montoUsdRecibido = 4_000_000 cents
        // delta = 4_000_000 - 5_000_000 = -1_000_000 (Loss)
        await factory.ventaCripto(
          eventId: EventId('evt-btc-venta-1'),
          deviceId: 'dev-btc',
          cuentaCriptoId: cuentaBtcId,
          cuentaDestinoUsdId: cuentaDestinoUsdId,
          cantidad: Money(
            amount: BigInt.from(100000000),
            currency: CurrencyCode('BTC'),
          ),
          montoUsdRecibido: Money(
            amount: BigInt.from(4000000),
            currency: CurrencyCode('USD'),
          ),
          rateRef: '40000.00 USD/BTC',
        );

        final event = store.events.last;
        expect(event.metadata.tipo, 'VentaCripto');
        expect(event.postings.length, 3);

        final pBtc = event.postings.firstWhere(
          (p) => p.target == CuentaTarget(cuentaBtcId),
        );
        expect(pBtc.amountUsd, -5000000); // costo_base
        expect(pBtc.amountNative.amount, BigInt.from(-100000000));

        final pUsd = event.postings.firstWhere(
          (p) => p.target == CuentaTarget(cuentaDestinoUsdId),
        );
        expect(pUsd.amountUsd, 4000000); // USD recibidos
        expect(pUsd.rateRef, '40000.00 USD/BTC');

        final pDiferencial = event.postings.firstWhere(
          (p) => p.target == SobreTarget(sobreDiferencialId),
        );
        expect(pDiferencial.amountUsd, -1000000); // 4M - 5M = -1M (loss)
      },
    );

    test(
      'Venta Cripto: genera 3 postings (Ganancia — BTC sube de precio)',
      () async {
        // BTC account: 1 BTC acquired at $30,000 (3_000_000 cents)
        // Current price: $45,000 → realiza ganancia de $15,000
        final cuentaBtcId = AccountId('acc-btc-2');
        final cuentaDestinoUsdId = AccountId('acc-usd-btc-2');
        final sobreDiferencialId = catalog.getSystemEnvelope(
          EnvelopeRole.diferencial,
        );

        catalog.saveAccount(
          Account(
            id: cuentaBtcId,
            name: 'BTC 2',
            nativeCurrency: CurrencyCode('BTC'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );
        catalog.saveAccount(
          Account(
            id: cuentaDestinoUsdId,
            name: 'USD dest 2',
            nativeCurrency: CurrencyCode('USD'),
            isArchived: false,
            updatedAt: DateTime.now(),
          ),
        );

        final initialEvent = Transaccion.crear(
          metadata: TransaccionMetadata(
            eventId: EventId('evt-btc2-init'),
            tipo: 'Apertura',
            occurredAt: DomainTimestamp(DateTime.now().toUtc()),
            recordedAt: DomainTimestamp(DateTime.now().toUtc()),
            deviceId: 'dev',
            schemaVersion: 1,
          ),
          postings: [
            Posting(
              target: CuentaTarget(cuentaBtcId),
              amountNative: Money(
                amount: BigInt.from(100000000),
                currency: CurrencyCode('BTC'),
              ),
              currency: CurrencyCode('BTC'),
              amountUsd: 3000000,
            ),
            Posting(
              target: SobreTarget(EnvelopeId('env-apertura')),
              amountNative: Money(
                amount: BigInt.from(3000000),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: 3000000,
            ),
          ],
        );
        projections.aplicar(initialEvent);

        // Sell all 1 BTC at $45,000 (4_500_000 cents)
        // delta = 4_500_000 - 3_000_000 = +1_500_000 (Gain)
        await factory.ventaCripto(
          eventId: EventId('evt-btc2-venta-1'),
          deviceId: 'dev-btc2',
          cuentaCriptoId: cuentaBtcId,
          cuentaDestinoUsdId: cuentaDestinoUsdId,
          cantidad: Money(
            amount: BigInt.from(100000000),
            currency: CurrencyCode('BTC'),
          ),
          montoUsdRecibido: Money(
            amount: BigInt.from(4500000),
            currency: CurrencyCode('USD'),
          ),
          rateRef: '45000.00 USD/BTC',
        );

        final event = store.events.last;

        final pBtc = event.postings.firstWhere(
          (p) => p.target == CuentaTarget(cuentaBtcId),
        );
        expect(pBtc.amountUsd, -3000000); // costo_base

        final pUsd = event.postings.firstWhere(
          (p) => p.target == CuentaTarget(cuentaDestinoUsdId),
        );
        expect(pUsd.amountUsd, 4500000);

        final pDiferencial = event.postings.firstWhere(
          (p) => p.target == SobreTarget(sobreDiferencialId),
        );
        expect(pDiferencial.amountUsd, 1500000); // gain
      },
    );
  });
}
