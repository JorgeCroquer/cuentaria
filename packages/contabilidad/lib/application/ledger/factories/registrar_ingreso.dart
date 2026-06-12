import 'package:shared_kernel/shared_kernel.dart';
import 'package:contabilidad/domain/transaccion_metadata.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/application/registrar_transaccion.dart';
import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/ledger/exceptions.dart';
import 'package:contabilidad/application/catalog/exceptions.dart';

class RegistrarIngreso {
  final RegistrarTransaccion _registrar;
  final CatalogRepository _catalog;

  RegistrarIngreso({
    required RegistrarTransaccion registrar,
    required CatalogRepository catalog,
  }) : _registrar = registrar,
       _catalog = catalog;

  Future<void> call({
    required EventId eventId,
    required String deviceId,
    required AccountId cuentaId,
    required Money monto,
    required String source,
    EnvelopeId? sobreId,
    DomainTimestamp? occurredAt,
  }) async {
    final cuenta = _catalog.getAccount(cuentaId);
    if (cuenta == null) {
      throw TargetInexistente('Cuenta no encontrada: $cuentaId');
    }

    if (cuenta.nativeCurrency != CurrencyCode('USD')) {
      throw OperacionSoloUSD();
    }

    final targetSobreId =
        sobreId ?? _catalog.getSystemEnvelope(EnvelopeRole.stage);

    if (monto.amount <= BigInt.zero) {
      throw ArgumentError('El monto debe ser estrictamente positivo.');
    }

    final amountUsd = monto.amount.toInt();

    final postings = [
      Posting(
        target: CuentaTarget(cuentaId),
        amountNative: monto,
        currency: monto.currency,
        amountUsd: amountUsd,
      ),
      Posting(
        target: SobreTarget(targetSobreId),
        amountNative: monto,
        currency: monto.currency,
        amountUsd: amountUsd,
      ),
    ];

    final now = DateTime.now().toUtc();
    final metadata = TransaccionMetadata(
      eventId: eventId,
      tipo: 'Ingreso',
      occurredAt: occurredAt ?? DomainTimestamp(now),
      recordedAt: DomainTimestamp(now),
      deviceId: deviceId,
      schemaVersion: 1,
      source: source,
    );

    await _registrar(postings: postings, metadata: metadata);
  }
}
