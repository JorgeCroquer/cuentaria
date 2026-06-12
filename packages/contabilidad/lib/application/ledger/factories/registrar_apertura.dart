import 'package:decimal/decimal.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:contabilidad/domain/transaccion_metadata.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/ports/ledger_projections.dart';
import 'package:contabilidad/application/registrar_transaccion.dart';
import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/catalog/exceptions.dart';

class RegistrarApertura {
  final RegistrarTransaccion _registrar;
  final CatalogRepository _catalog;
  final LedgerProjections _projections;

  RegistrarApertura({
    required RegistrarTransaccion registrar,
    required CatalogRepository catalog,
    required LedgerProjections projections,
  })  : _registrar = registrar,
        _catalog = catalog,
        _projections = projections;

  Future<void> call({
    required EventId eventId,
    required String deviceId,
    required AccountId cuentaId,
    required Money montoNative,
    int? amountUsd,
    Decimal? rate,
    DomainTimestamp? occurredAt,
  }) async {
    final cuenta = _catalog.getAccount(cuentaId);
    if (cuenta == null) {
      throw TargetInexistente('Cuenta no encontrada: $cuentaId');
    }
    
    // Guard de re-apertura
    final saldoActual = _projections.saldoCuenta(cuentaId);
    if (saldoActual.native.amount != BigInt.zero) {
      throw ArgumentError('La cuenta ya tiene saldo, no se puede abrir de nuevo.');
    }

    int usdCostBase;
    
    if (cuenta.nativeCurrency == CurrencyCode('USD')) {
      usdCostBase = montoNative.amount.toInt();
    } else {
      if (amountUsd != null) {
        usdCostBase = amountUsd;
      } else if (rate != null) {
        final decMonto = Decimal.fromBigInt(montoNative.amount);
        usdCostBase = (decMonto * rate).round().toBigInt().toInt();
      } else {
        throw ArgumentError('Para cuentas extranjeras debe proveer amountUsd o rate.');
      }
    }

    final sobreAperturaId = _catalog.getSystemEnvelope(EnvelopeRole.apertura);

    final postings = [
      Posting(
        target: CuentaTarget(cuentaId),
        amountNative: montoNative,
        currency: montoNative.currency,
        amountUsd: usdCostBase,
        rateRef: rate != null ? '${rate.toDouble().toStringAsFixed(2)} ${montoNative.currency.value}/USD' : null,
      ),
      Posting(
        target: SobreTarget(sobreAperturaId),
        amountNative: Money(amount: BigInt.from(usdCostBase), currency: CurrencyCode('USD')),
        currency: CurrencyCode('USD'),
        amountUsd: usdCostBase,
      ),
    ];

    final now = DateTime.now().toUtc();
    final metadata = TransaccionMetadata(
      eventId: eventId,
      tipo: 'Apertura',
      occurredAt: occurredAt ?? DomainTimestamp(now),
      recordedAt: DomainTimestamp(now),
      deviceId: deviceId,
      schemaVersion: 1,
    );

    await _registrar(postings: postings, metadata: metadata);
  }
}
