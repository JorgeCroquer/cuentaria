import 'package:backup/backup.dart';
import 'package:test/test.dart';

void main() {
  group('BackupReaderError messages', () {
    test('UnknownFormatVersion names the format and no line number', () {
      const error = UnknownFormatVersion(9);

      expect(error.message, contains('9'));
      expect(error.message, isNot(contains('renglón')));
    });

    test('InvalidHeader names no line number', () {
      const error = InvalidHeader('el archivo está vacío');

      expect(error.message, contains('encabezado'));
      expect(error.message, isNot(contains('renglón')));
    });

    test('InvalidLine names the line number and the reason', () {
      const error = InvalidLine(lineNumber: 47, reason: 'está incompleto');

      expect(error.message, equals('el renglón 47 está incompleto'));
    });

    test('TruncatedFile names expected vs actual counts', () {
      const error = TruncatedFile(expected: 'event: 2', actual: 'event: 1');

      expect(error.message, contains('event: 2'));
      expect(error.message, contains('event: 1'));
    });

    test('every error variant produces a distinguishable message', () {
      const errors = <BackupReaderError>[
        UnknownFormatVersion(9),
        InvalidHeader('el archivo está vacío'),
        TruncatedFile(expected: 'event: 2', actual: 'event: 1'),
        InvalidLine(lineNumber: 3, reason: 'está incompleto'),
      ];

      final messages = errors.map((e) => e.message).toSet();
      expect(messages, hasLength(errors.length));
    });
  });
}
