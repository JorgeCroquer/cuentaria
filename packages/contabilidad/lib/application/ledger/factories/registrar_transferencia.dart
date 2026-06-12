import 'package:shared_kernel/shared_kernel.dart';
import 'package:contabilidad/domain/transaccion_metadata.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/application/registrar_transaccion.dart';
import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/application/ledger/exceptions.dart';
import 'package:contabilidad/application/catalog/exceptions.dart';

class RegistrarTransferencia {
  final RegistrarTransaccion _registrar;
  final CatalogRepository _catalog;

  RegistrarTransferencia({
    required RegistrarTransaccion registrar,
    required CatalogRepository catalog,
  }) : _registrar = registrar,
       _catalog = catalog;

  Future<void> call({
    required EventId eventId,
    required String deviceId,
    required AccountId cuentaOrigenId,
    required AccountId cuentaDestinoId,
    required Money monto,
    DomainTimestamp? occurredAt,
  }) async {
    final origen = _catalog.getAccount(cuentaOrigenId);
    if (origen == null) {
      throw TargetInexistente('Cuenta origen no encontrada: $cuentaOrigenId');
    }

    final destino = _catalog.getAccount(cuentaDestinoId);
    if (destino == null) {
      throw TargetInexistente('Cuenta destino no encontrada: $cuentaDestinoId');
    }

    if (origen.nativeCurrency != destino.nativeCurrency) {
      throw TransferenciaMonedaCruzada();
    }

    if (origen.nativeCurrency != CurrencyCode('USD')) {
      throw OperacionSoloUSD();
    }

    if (monto.amount <= BigInt.zero) {
      throw ArgumentError('El monto debe ser estrictamente positivo.');
    }

    final amountUsd = monto.amount.toInt();
    final negatedMonto = Money(amount: -monto.amount, currency: monto.currency);

    final postings = [
      Posting(
        target: CuentaTarget(cuentaOrigenId),
        amountNative: negatedMonto,
        currency: monto.currency,
        amountUsd: -amountUsd,
      ),
      Posting(
        target: CuentaTarget(cuentaDestinoId),
        amountNative: monto,
        currency: monto.currency,
        amountUsd: amountUsd,
      ),
    ];

    final now = DateTime.now().toUtc();
    final metadata = TransaccionMetadata(
      eventId: eventId,
      tipo: 'Transferencia',
      occurredAt: occurredAt ?? DomainTimestamp(now),
      recordedAt: DomainTimestamp(now),
      deviceId: deviceId,
      schemaVersion: 1,
    );

    await _registrar(postings: postings, metadata: metadata);
  }
}
