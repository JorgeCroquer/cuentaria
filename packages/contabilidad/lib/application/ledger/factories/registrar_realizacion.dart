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
      throw ArgumentError('Esta factory es para moneda extranjera, no USD.');
    }

    final saldo = _projections.saldoCuenta(cuentaId);
    if (montoNative.amount > saldo.native.amount) {
      throw SaldoInsuficiente('El monto a disponer supera el saldo de la cuenta');
    }

    final sobreDestino = _catalog.getEnvelope(sobreDestinoId);
    if (sobreDestino == null) {
      throw TargetInexistente('Sobre destino no encontrado: $sobreDestinoId');
    }

    final sobreDiferencialId = _catalog.getSystemEnvelope(EnvelopeRole.diferencial);

    final decMonto = Decimal.fromBigInt(montoNative.amount);
    final valorMercado = (decMonto / tasaActual).round().toInt();
    final costoBase = saldo.costoBaseDe(montoNative.amount);
    final delta = valorMercado - costoBase;

    final negatedNative = Money(amount: -montoNative.amount, currency: montoNative.currency);
    final negatedUsdMoney = Money(amount: BigInt.from(-valorMercado), currency: CurrencyCode('USD'));
    final deltaUsdMoney = Money(amount: BigInt.from(delta), currency: CurrencyCode('USD'));

    final postings = [
      Posting(
        target: CuentaTarget(cuentaId),
        amountNative: negatedNative,
        currency: montoNative.currency,
        amountUsd: -costoBase,
      ),
      Posting(
        target: SobreTarget(sobreDestinoId),
        amountNative: negatedUsdMoney,
        currency: CurrencyCode('USD'),
        amountUsd: -valorMercado,
      ),
      Posting(
        target: SobreTarget(sobreDiferencialId),
        amountNative: deltaUsdMoney,
        currency: CurrencyCode('USD'),
        amountUsd: delta,
      ),
    ];

    final now = DateTime.now().toUtc();
    final metadata = TransaccionMetadata(
      eventId: eventId,
      tipo: 'GastoMonedaExtranjera',
      occurredAt: occurredAt ?? DomainTimestamp(now),
      recordedAt: DomainTimestamp(now),
      deviceId: deviceId,
      schemaVersion: 1,
    );

    await _registrar(postings: postings, metadata: metadata);
  }

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
      throw ArgumentError('La cuenta origen debe ser moneda extranjera');
    }

    final cuentaDestino = _catalog.getAccount(cuentaDestinoUsdId);
    if (cuentaDestino == null) {
      throw TargetInexistente('Cuenta destino no encontrada: $cuentaDestinoUsdId');
    }
    if (cuentaDestino.nativeCurrency != CurrencyCode('USD')) {
      throw ArgumentError('La cuenta destino debe ser USD');
    }

    final saldo = _projections.saldoCuenta(cuentaOrigenExtId);
    if (montoNative.amount > saldo.native.amount) {
      throw SaldoInsuficiente('El monto a disponer supera el saldo de la cuenta');
    }

    final sobreDiferencialId = _catalog.getSystemEnvelope(EnvelopeRole.diferencial);

    final valorObservado = montoUsdRecibido.amount.toInt();
    final costoBase = saldo.costoBaseDe(montoNative.amount);
    final delta = valorObservado - costoBase;

    final negatedNative = Money(amount: -montoNative.amount, currency: montoNative.currency);
    final deltaUsdMoney = Money(amount: BigInt.from(delta), currency: CurrencyCode('USD'));

    final postings = [
      Posting(
        target: CuentaTarget(cuentaOrigenExtId),
        amountNative: negatedNative,
        currency: montoNative.currency,
        amountUsd: -costoBase,
      ),
      Posting(
        target: CuentaTarget(cuentaDestinoUsdId),
        amountNative: montoUsdRecibido,
        currency: CurrencyCode('USD'),
        amountUsd: valorObservado,
        rateRef: rateRef,
      ),
      Posting(
        target: SobreTarget(sobreDiferencialId),
        amountNative: deltaUsdMoney,
        currency: CurrencyCode('USD'),
        amountUsd: delta,
      ),
    ];

    final now = DateTime.now().toUtc();
    final metadata = TransaccionMetadata(
      eventId: eventId,
      tipo: 'ConversionDisposicion',
      occurredAt: occurredAt ?? DomainTimestamp(now),
      recordedAt: DomainTimestamp(now),
      deviceId: deviceId,
      schemaVersion: 1,
    );

    await _registrar(postings: postings, metadata: metadata);
  }
}
