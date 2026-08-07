import 'package:shared_kernel/shared_kernel.dart';

/// One row of the CSV Export (ADR-0021 §8): one row per Ledger [Posting],
/// not per movement — a Transaction can touch one account and several
/// envelopes at once.
class CsvRow {
  final DateTime fecha;
  final String tipo;
  final String memo;
  final String dimension;
  final String nombre;
  final Money montoNativo;
  final int montoUsdCents;
  final String tasa;
  final String eventId;

  const CsvRow({
    required this.fecha,
    required this.tipo,
    required this.memo,
    required this.dimension,
    required this.nombre,
    required this.montoNativo,
    required this.montoUsdCents,
    required this.tasa,
    required this.eventId,
  });
}
