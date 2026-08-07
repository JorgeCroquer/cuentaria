import 'csv_row.dart';

const _header =
    'fecha,tipo,memo,dimension,nombre,monto_nativo,moneda,'
    'monto_usd,tasa,event_id';

/// Serializes [CsvRow]s to CSV text (ADR-0021 §8), one file for the
/// "Exportar a Excel" button. Money is written as decimal text built
/// straight from minor-unit `BigInt`s/`int`s — never through a `double` —
/// so it never renders in scientific notation.
///
/// Rows are written in the order given; the caller (app layer) is
/// responsible for the canonical `occurred_at -> recorded_at -> event_id`
/// order, matching how `BackupWriter` takes its lines pre-ordered too.
class CsvWriter {
  const CsvWriter();

  String writeCsv(List<CsvRow> rows) {
    final lines = <String>[_header];
    for (final row in rows) {
      lines.add(_rowLine(row));
    }
    return lines.join('\n');
  }

  String _rowLine(CsvRow row) {
    final fields = [
      row.fecha.toUtc().toIso8601String(),
      row.tipo,
      row.memo,
      row.dimension,
      row.nombre,
      _formatMinorUnits(row.montoNativo.amount),
      row.montoNativo.currency.value,
      _formatMinorUnits(BigInt.from(row.montoUsdCents)),
      row.tasa,
      row.eventId,
    ];
    return fields.map(_escape).join(',');
  }

  static String _formatMinorUnits(BigInt cents) {
    final negative = cents.isNegative;
    final digits = cents.abs().toString().padLeft(3, '0');
    final whole = digits.substring(0, digits.length - 2);
    final fraction = digits.substring(digits.length - 2);
    return '${negative ? '-' : ''}$whole.$fraction';
  }

  static String _escape(String field) {
    final needsQuoting =
        field.contains(',') || field.contains('"') || field.contains('\n');
    if (!needsQuoting) return field;
    return '"${field.replaceAll('"', '""')}"';
  }
}
