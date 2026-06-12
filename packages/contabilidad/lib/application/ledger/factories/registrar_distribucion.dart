import 'package:shared_kernel/shared_kernel.dart';
import 'package:contabilidad/domain/transaccion_metadata.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/application/registrar_transaccion.dart';
import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/application/catalog/exceptions.dart';

class MovimientoDistribucion {
  final EnvelopeId sobreId;
  final int amountUsd;

  MovimientoDistribucion({required this.sobreId, required this.amountUsd});
}

class RegistrarDistribucion {
  final RegistrarTransaccion _registrar;
  final CatalogRepository _catalog;

  RegistrarDistribucion({
    required RegistrarTransaccion registrar,
    required CatalogRepository catalog,
  })  : _registrar = registrar,
        _catalog = catalog;

  Future<void> call({
    required EventId eventId,
    required String deviceId,
    required List<MovimientoDistribucion> movimientos,
    DomainTimestamp? occurredAt,
  }) async {
    int sum = movimientos.fold(0, (acc, m) => acc + m.amountUsd);
    if (sum != 0) {
      throw ArgumentError('Los movimientos de distribución deben sumar 0. Suma actual: $sum');
    }

    final postings = movimientos.map((m) {
      final sobre = _catalog.getEnvelope(m.sobreId);
      if (sobre == null) {
        throw TargetInexistente('Sobre no encontrado: ${m.sobreId.value}');
      }
      return Posting(
        target: SobreTarget(m.sobreId),
        amountNative: Money(amount: BigInt.from(m.amountUsd), currency: CurrencyCode('USD')),
        currency: CurrencyCode('USD'),
        amountUsd: m.amountUsd,
      );
    }).toList();

    final now = DateTime.now().toUtc();
    final metadata = TransaccionMetadata(
      eventId: eventId,
      tipo: 'Distribucion',
      occurredAt: occurredAt ?? DomainTimestamp(now),
      recordedAt: DomainTimestamp(now),
      deviceId: deviceId,
      schemaVersion: 1,
    );

    await _registrar(postings: postings, metadata: metadata);
  }
}
