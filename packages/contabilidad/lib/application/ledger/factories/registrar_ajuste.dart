import 'package:shared_kernel/shared_kernel.dart';
import 'package:contabilidad/domain/transaccion_metadata.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/application/registrar_transaccion.dart';
import 'package:contabilidad/domain/ports/ledger_projections.dart';
import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/application/ledger/exceptions.dart';
import 'package:contabilidad/application/catalog/exceptions.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';

class RegistrarAjuste {
  final RegistrarTransaccion _registrar;
  final LedgerProjections _projections;
  final CatalogRepository _catalog;

  RegistrarAjuste({
    required RegistrarTransaccion registrar,
    required LedgerProjections projections,
    required CatalogRepository catalog,
  })  : _registrar = registrar,
        _projections = projections,
        _catalog = catalog;

  Future<void> call({
    required EventId eventId,
    required String deviceId,
    required AccountId cuentaId,
    required Money saldoRealNative,
    DomainTimestamp? occurredAt,
  }) async {
    final cuenta = _catalog.getAccount(cuentaId);
    if (cuenta == null) {
      throw TargetInexistente('Cuenta no encontrada: $cuentaId');
    }

    if (saldoRealNative.currency != cuenta.nativeCurrency) {
      throw ArgumentError('La moneda del saldo real debe coincidir con la de la cuenta.');
    }

    final saldoProyectado = _projections.saldoCuenta(cuentaId);
    final deltaNative = saldoRealNative.amount - saldoProyectado.native.amount;

    if (deltaNative == BigInt.zero) {
      throw AjusteSinDiferencia();
    }

    if (deltaNative > BigInt.zero && cuenta.nativeCurrency != CurrencyCode('USD')) {
      throw AjustePositivoMonedaExtranjeraNoPermitido();
    }

    final int amountUsd;
    if (cuenta.nativeCurrency == CurrencyCode('USD')) {
      amountUsd = deltaNative.toInt();
    } else {
      final costBasis = saldoProyectado.costoBaseDe(deltaNative.abs());
      amountUsd = -costBasis;
    }

    final ajustesId = _catalog.getSystemEnvelope(EnvelopeRole.ajustes);

    final postings = [
      Posting(
        target: CuentaTarget(cuentaId),
        amountNative: Money(amount: deltaNative, currency: cuenta.nativeCurrency),
        currency: cuenta.nativeCurrency,
        amountUsd: amountUsd,
      ),
      Posting(
        target: SobreTarget(ajustesId),
        amountNative: Money(amount: BigInt.from(amountUsd), currency: CurrencyCode('USD')),
        currency: CurrencyCode('USD'),
        amountUsd: amountUsd,
      ),
    ];

    final now = DateTime.now().toUtc();
    final metadata = TransaccionMetadata(
      eventId: eventId,
      tipo: 'Ajuste',
      occurredAt: occurredAt ?? DomainTimestamp(now),
      recordedAt: DomainTimestamp(now),
      deviceId: deviceId,
      schemaVersion: 1,
    );

    await _registrar(postings: postings, metadata: metadata);
  }
}
