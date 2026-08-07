import 'package:backup/backup.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:test/test.dart';

CsvRow _row({
  DateTime? fecha,
  String tipo = 'Expense',
  String memo = '',
  String dimension = 'cuenta',
  String nombre = 'Efectivo',
  BigInt? montoNativoAmount,
  String moneda = 'USD',
  int montoUsdCents = 1182,
  String tasa = '',
  String eventId = 'evt-1',
}) => CsvRow(
  fecha: fecha ?? DateTime.utc(2026, 8, 1, 12, 30),
  tipo: tipo,
  memo: memo,
  dimension: dimension,
  nombre: nombre,
  montoNativo: Money(
    amount: montoNativoAmount ?? BigInt.from(1182),
    currency: CurrencyCode(moneda),
  ),
  montoUsdCents: montoUsdCents,
  tasa: tasa,
  eventId: eventId,
);

void main() {
  group('CsvWriter.writeCsv', () {
    const writer = CsvWriter();

    test('writes the canonical header as the first line', () {
      final csv = writer.writeCsv(const []);
      expect(
        csv,
        equals(
          'fecha,tipo,memo,dimension,nombre,monto_nativo,moneda,'
          'monto_usd,tasa,event_id',
        ),
      );
    });

    test('writes one data line per row, in the given order', () {
      final csv = writer.writeCsv([
        _row(eventId: 'evt-1', dimension: 'cuenta', nombre: 'Efectivo'),
        _row(eventId: 'evt-1', dimension: 'sobre', nombre: 'Alquiler'),
      ]);

      final lines = csv.split('\n');
      expect(lines, hasLength(3));
      expect(lines[1], contains('cuenta,Efectivo'));
      expect(lines[2], contains('sobre,Alquiler'));
    });

    test(
      'formats money as decimal text, never scientific notation or double',
      () {
        // 10.000 Bs valued at 845.88 VES/USD -> 11.82 USD.
        final csv = writer.writeCsv([
          _row(
            montoNativoAmount: BigInt.from(1000000),
            moneda: 'VES',
            montoUsdCents: 1182,
            tasa: '845.88 VES/USD',
          ),
        ]);

        final fields = csv.split('\n')[1].split(',');
        expect(fields[5], equals('10000.00')); // monto_nativo
        expect(fields[6], equals('VES')); // moneda
        expect(fields[7], equals('11.82')); // monto_usd
        expect(fields[8], equals('845.88 VES/USD')); // tasa
      },
    );

    test('formats negative cents with a leading minus sign', () {
      final csv = writer.writeCsv([
        _row(montoNativoAmount: BigInt.from(-1182), montoUsdCents: -1182),
      ]);

      final fields = csv.split('\n')[1].split(',');
      expect(fields[5], equals('-11.82'));
      expect(fields[7], equals('-11.82'));
    });

    test('formats cent amounts under one unit with the leading zero', () {
      final csv = writer.writeCsv([
        _row(montoNativoAmount: BigInt.from(5), montoUsdCents: 5),
      ]);

      final fields = csv.split('\n')[1].split(',');
      expect(fields[5], equals('0.05'));
      expect(fields[7], equals('0.05'));
    });

    test('escapes a memo containing a comma by quoting the field', () {
      final csv = writer.writeCsv([_row(memo: 'pan, leche')]);
      expect(csv.split('\n')[1], contains('"pan, leche"'));
    });

    test('escapes a memo containing a quote by doubling it', () {
      final csv = writer.writeCsv([_row(memo: 'el "mejor" precio')]);
      expect(csv.split('\n')[1], contains('"el ""mejor"" precio"'));
    });

    test('escapes a memo containing a newline by quoting the field', () {
      final csv = writer.writeCsv([_row(memo: 'linea 1\nlinea 2')]);
      expect(csv, contains('"linea 1\nlinea 2"'));
    });

    test('a two-leg transaction produces two rows with the same event_id', () {
      final rows = [
        _row(eventId: 'evt-1', dimension: 'cuenta'),
        _row(eventId: 'evt-1', dimension: 'sobre'),
      ];
      final csv = writer.writeCsv(rows);
      final lines = csv.split('\n').skip(1);
      expect(lines, everyElement(contains('evt-1')));
      expect(lines, hasLength(2));
    });

    test(
      'a one-to-three distribution produces four rows with the same event_id',
      () {
        final rows = [
          _row(eventId: 'evt-1', dimension: 'sobre', nombre: 'Origen'),
          _row(eventId: 'evt-1', dimension: 'sobre', nombre: 'Destino 1'),
          _row(eventId: 'evt-1', dimension: 'sobre', nombre: 'Destino 2'),
          _row(eventId: 'evt-1', dimension: 'sobre', nombre: 'Destino 3'),
        ];
        final csv = writer.writeCsv(rows);
        final lines = csv.split('\n').skip(1);
        expect(lines, everyElement(contains('evt-1')));
        expect(lines, hasLength(4));
      },
    );
  });
}
