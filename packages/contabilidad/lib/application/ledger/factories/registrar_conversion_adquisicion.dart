import 'package:shared_kernel/shared_kernel.dart';
import 'package:contabilidad/domain/transaccion_metadata.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/application/registrar_transaccion.dart';
import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/application/ledger/exceptions.dart';
import 'package:contabilidad/application/catalog/exceptions.dart';

class RegistrarConversionAdquisicion {
  final RegistrarTransaccion _registrar;
  final CatalogRepository _catalog;

  RegistrarConversionAdquisicion({
    required RegistrarTransaccion registrar,
    required CatalogRepository catalog,
  })  : _registrar = registrar,
        _catalog = catalog;

  Future<void> call({
    required EventId eventId,
    required String deviceId,
    required AccountId cuentaOrigenUsdId,
    required AccountId cuentaDestinoExtId,
    required Money montoUsd,
    required Money montoExtRecibido,
    required String rateRef,
    DomainTimestamp? occurredAt,
  }) async {
    final origen = _catalog.getAccount(cuentaOrigenUsdId);
    if (origen == null) {
      throw TargetInexistente('Cuenta origen no encontrada: $cuentaOrigenUsdId');
    }

    final destino = _catalog.getAccount(cuentaDestinoExtId);
    if (destino == null) {
      throw TargetInexistente('Cuenta destino no encontrada: $cuentaDestinoExtId');
    }

    if (origen.nativeCurrency != CurrencyCode('USD')) {
      throw OperacionSoloUSD();
    }

    if (destino.nativeCurrency == CurrencyCode('USD')) {
      throw ArgumentError('La cuenta destino no puede ser USD en una adquisición de moneda extranjera.');
    }

    if (montoUsd.amount <= BigInt.zero || montoExtRecibido.amount <= BigInt.zero) {
      throw ArgumentError('Los montos deben ser estrictamente positivos.');
    }

    final amountUsdInt = montoUsd.amount.toInt();

    final postings = [
      Posting(
        target: CuentaTarget(cuentaOrigenUsdId),
        amountNative: Money(amount: -montoUsd.amount, currency: montoUsd.currency),
        currency: montoUsd.currency,
        amountUsd: -amountUsdInt,
      ),
      Posting(
        target: CuentaTarget(cuentaDestinoExtId),
        amountNative: montoExtRecibido,
        currency: montoExtRecibido.currency,
        amountUsd: amountUsdInt,
        rateRef: rateRef,
      ),
    ];

    final now = DateTime.now().toUtc();
    final metadata = TransaccionMetadata(
      eventId: eventId,
      tipo: 'ConversionAdquisicion',
      occurredAt: occurredAt ?? DomainTimestamp(now),
      recordedAt: DomainTimestamp(now),
      deviceId: deviceId,
      schemaVersion: 1,
    );

    await _registrar(postings: postings, metadata: metadata);
  }
}
