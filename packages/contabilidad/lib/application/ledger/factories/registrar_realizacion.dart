import 'package:decimal/decimal.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:contabilidad/domain/ports/ledger_projections.dart';
import 'package:contabilidad/application/registrar_transaccion.dart';
import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/application/ledger/exceptions.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/transaccion_metadata.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/catalog/exceptions.dart';

class RegistrarRealizacion {
  final RegistrarTransaccion _registrar;
  final CatalogRepository _catalog;
  final LedgerProjections _projections;

  RegistrarRealizacion({
    required RegistrarTransaccion registrar,
    required CatalogRepository catalog,
    required LedgerProjections projections,
  })  : _registrar = registrar,
        _catalog = catalog,
        _projections = projections;

  // Disposes a foreign-currency account balance via an expense envelope.
  Future<void> gastoMonedaExtranjera({
    required EventId eventId,
    required String deviceId,
    required AccountId cuentaId,
    required EnvelopeId sobreDestinoId,
    required Money montoNative,
    required Decimal tasaActual,
    DomainTimestamp? occurredAt,
  }) async {
    final cuenta = _catalog.getAccount(cuentaId);
    if (cuenta == null) {
      throw TargetInexistente('Cuenta no encontrada: $cuentaId');
    }
    if (cuenta.nativeCurrency == CurrencyCode('USD')) {
      throw MonedaIncompatible('Esta factory es para moneda extranjera, no USD.');
    }

    final sobreDestino = _catalog.getEnvelope(sobreDestinoId);
    if (sobreDestino == null) {
      throw TargetInexistente('Sobre destino no encontrado: $sobreDestinoId');
    }

    final saldo = _projections.saldoCuenta(cuentaId);
    if (montoNative.amount > saldo.native.amount) {
      throw SaldoInsuficiente('El monto a disponer supera el saldo de la cuenta');
    }

    final decMonto = Decimal.fromBigInt(montoNative.amount);
    final valorMercado = (decMonto / tasaActual).round().toInt();
    final rateRef = '${tasaActual.toDouble().toStringAsFixed(2)} ${montoNative.currency.value}/USD';

    await _realizarDisposicion(
      eventId: eventId,
      deviceId: deviceId,
      tipo: 'GastoMonedaExtranjera',
      cuentaOrigenId: cuentaId,
      montoNative: montoNative,
      costoBase: saldo.costoBaseDe(montoNative.amount),
      valorObservadoUsd: valorMercado,
      destinoPosting: Posting(
        target: SobreTarget(sobreDestinoId),
        amountNative: Money(amount: BigInt.from(-valorMercado), currency: CurrencyCode('USD')),
        currency: CurrencyCode('USD'),
        amountUsd: -valorMercado,
        rateRef: rateRef,
      ),
      occurredAt: occurredAt,
    );
  }

  // Disposes a foreign-currency account balance converting it to a USD account.
  // Uses the observed USD received (not an inferred rate) for the accounting.
  Future<void> conversionDisposicion({
    required EventId eventId,
    required String deviceId,
    required AccountId cuentaOrigenExtId,
    required AccountId cuentaDestinoUsdId,
    required Money montoNative,
    required Money montoUsdRecibido,
    required String rateRef,
    DomainTimestamp? occurredAt,
  }) async {
    final cuentaOrigen = _catalog.getAccount(cuentaOrigenExtId);
    if (cuentaOrigen == null) {
      throw TargetInexistente('Cuenta origen no encontrada: $cuentaOrigenExtId');
    }
    if (cuentaOrigen.nativeCurrency == CurrencyCode('USD')) {
      throw MonedaIncompatible('La cuenta origen debe ser moneda extranjera, no USD.');
    }

    final cuentaDestino = _catalog.getAccount(cuentaDestinoUsdId);
    if (cuentaDestino == null) {
      throw TargetInexistente('Cuenta destino no encontrada: $cuentaDestinoUsdId');
    }
    if (cuentaDestino.nativeCurrency != CurrencyCode('USD')) {
      throw MonedaIncompatible('La cuenta destino debe ser USD.');
    }

    final saldo = _projections.saldoCuenta(cuentaOrigenExtId);
    if (montoNative.amount > saldo.native.amount) {
      throw SaldoInsuficiente('El monto a disponer supera el saldo de la cuenta');
    }

    final valorObservado = montoUsdRecibido.amount.toInt();

    await _realizarDisposicion(
      eventId: eventId,
      deviceId: deviceId,
      tipo: 'ConversionDisposicion',
      cuentaOrigenId: cuentaOrigenExtId,
      montoNative: montoNative,
      costoBase: saldo.costoBaseDe(montoNative.amount),
      valorObservadoUsd: valorObservado,
      destinoPosting: Posting(
        target: CuentaTarget(cuentaDestinoUsdId),
        amountNative: montoUsdRecibido,
        currency: CurrencyCode('USD'),
        amountUsd: valorObservado,
        rateRef: rateRef,
      ),
      occurredAt: occurredAt,
    );
  }

  // Sells a crypto asset to a USD account using the observed proceeds.
  Future<void> ventaCripto({
    required EventId eventId,
    required String deviceId,
    required AccountId cuentaCriptoId,
    required AccountId cuentaDestinoUsdId,
    required Money cantidad,
    required Money montoUsdRecibido,
    required String rateRef,
    DomainTimestamp? occurredAt,
  }) async {
    final cuentaCripto = _catalog.getAccount(cuentaCriptoId);
    if (cuentaCripto == null) {
      throw TargetInexistente('Cuenta cripto no encontrada: $cuentaCriptoId');
    }
    if (cuentaCripto.nativeCurrency == CurrencyCode('USD')) {
      throw MonedaIncompatible('La cuenta cripto no puede ser USD.');
    }

    final cuentaDestino = _catalog.getAccount(cuentaDestinoUsdId);
    if (cuentaDestino == null) {
      throw TargetInexistente('Cuenta destino no encontrada: $cuentaDestinoUsdId');
    }
    if (cuentaDestino.nativeCurrency != CurrencyCode('USD')) {
      throw MonedaIncompatible('La cuenta destino debe ser USD.');
    }

    final saldo = _projections.saldoCuenta(cuentaCriptoId);
    if (cantidad.amount > saldo.native.amount) {
      throw SaldoInsuficiente('La cantidad a vender supera el saldo de la cuenta');
    }

    final valorObservado = montoUsdRecibido.amount.toInt();

    await _realizarDisposicion(
      eventId: eventId,
      deviceId: deviceId,
      tipo: 'VentaCripto',
      cuentaOrigenId: cuentaCriptoId,
      montoNative: cantidad,
      costoBase: saldo.costoBaseDe(cantidad.amount),
      valorObservadoUsd: valorObservado,
      destinoPosting: Posting(
        target: CuentaTarget(cuentaDestinoUsdId),
        amountNative: montoUsdRecibido,
        currency: CurrencyCode('USD'),
        amountUsd: valorObservado,
        rateRef: rateRef,
      ),
      occurredAt: occurredAt,
    );
  }

  // Single implementation shared by all three public faces.
  // Generates the canonical 3-posting realization pattern:
  //   −C activo (costo_base), destino (valor_observado), ±S Diferencial (delta).
  Future<void> _realizarDisposicion({
    required EventId eventId,
    required String deviceId,
    required String tipo,
    required AccountId cuentaOrigenId,
    required Money montoNative,
    required int costoBase,
    required int valorObservadoUsd,
    required Posting destinoPosting,
    DomainTimestamp? occurredAt,
  }) async {
    final sobreDiferencialId = _catalog.getSystemEnvelope(EnvelopeRole.diferencial);
    final delta = valorObservadoUsd - costoBase;

    final postings = [
      Posting(
        target: CuentaTarget(cuentaOrigenId),
        amountNative: Money(amount: -montoNative.amount, currency: montoNative.currency),
        currency: montoNative.currency,
        amountUsd: -costoBase,
      ),
      destinoPosting,
      Posting(
        target: SobreTarget(sobreDiferencialId),
        amountNative: Money(amount: BigInt.from(delta), currency: CurrencyCode('USD')),
        currency: CurrencyCode('USD'),
        amountUsd: delta,
      ),
    ];

    final now = DateTime.now().toUtc();
    final metadata = TransaccionMetadata(
      eventId: eventId,
      tipo: tipo,
      occurredAt: occurredAt ?? DomainTimestamp(now),
      recordedAt: DomainTimestamp(now),
      deviceId: deviceId,
      schemaVersion: 1,
    );

    await _registrar(postings: postings, metadata: metadata);
  }
}
