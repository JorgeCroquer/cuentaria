import 'package:shared_kernel/shared_kernel.dart';
import 'package:contabilidad/domain/transaccion_metadata.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/application/registrar_transaccion.dart';
import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/application/ledger/exceptions.dart';
import 'package:contabilidad/application/catalog/exceptions.dart';

class RegistrarGastoUsd {
  final RegistrarTransaccion _registrar;
  final CatalogRepository _catalog;

  RegistrarGastoUsd({
    required RegistrarTransaccion registrar,
    required CatalogRepository catalog,
  })  : _registrar = registrar,
        _catalog = catalog;

  Future<void> call({
    required EventId eventId,
    required String deviceId,
    required AccountId cuentaId,
    required EnvelopeId sobreId,
    required Money monto,
    DomainTimestamp? occurredAt,
  }) async {
    final cuenta = _catalog.getAccount(cuentaId);
    if (cuenta == null) {
      throw TargetInexistente('Cuenta no encontrada: $cuentaId');
    }

    if (cuenta.nativeCurrency != CurrencyCode('USD')) {
      throw OperacionSoloUSD();
    }

    final amountUsd = monto.amount.toInt();
    final negatedMonto = Money(amount: -monto.amount, currency: monto.currency);

    final postings = [
      Posting(
        target: CuentaTarget(cuentaId),
        amountNative: negatedMonto,
        currency: monto.currency,
        amountUsd: -amountUsd,
      ),
      Posting(
        target: SobreTarget(sobreId),
        amountNative: negatedMonto,
        currency: monto.currency,
        amountUsd: -amountUsd,
      ),
    ];

    final metadata = TransaccionMetadata(
      eventId: eventId,
      tipo: 'Gasto',
      occurredAt: occurredAt ?? DomainTimestamp(DateTime.now().toUtc()),
      recordedAt: DomainTimestamp(DateTime.now().toUtc()),
      deviceId: deviceId,
      schemaVersion: 1,
    );

    await _registrar(postings: postings, metadata: metadata);
  }
}
