import 'package:backup/backup.dart';
import 'package:test/test.dart';

const _validHeader =
    '{"kind":"header","format":1,"app":"cuentaria",'
    '"exportedAt":"2026-01-01T00:00:00.000Z",'
    '"counts":{"event":0,"account":1,"envelope":0,"cascade":0,"rate":0}}';

void main() {
  group('BackupReader rejections', () {
    const reader = BackupReader();

    test('empty file is rejected as an invalid header, not a line error', () {
      expect(() => reader.parse(''), throwsA(isA<InvalidHeader>()));
    });

    test('a file without a header is rejected as invalid, not as line 1', () {
      final ndjson = '{"kind":"account","data":{"id":"a"}}';

      expect(() => reader.parse(ndjson), throwsA(isA<InvalidHeader>()));
    });

    test('an unknown format version is rejected distinctly', () {
      final ndjson =
          '{"kind":"header","format":9,"app":"cuentaria",'
          '"exportedAt":"2026-01-01T00:00:00.000Z",'
          '"counts":{"event":0,"account":0,"envelope":0,"cascade":0,"rate":0}}';

      expect(
        () => reader.parse(ndjson),
        throwsA(
          isA<UnknownFormatVersion>().having(
            (e) => e.formatVersion,
            'formatVersion',
            9,
          ),
        ),
      );
    });

    test('invalid JSON on a data line names its line number', () {
      final ndjson = '$_validHeader\nnot json at all';

      expect(
        () => reader.parse(ndjson),
        throwsA(
          isA<InvalidLine>().having((e) => e.lineNumber, 'lineNumber', 2),
        ),
      );
    });

    test('an unknown kind names its line number', () {
      final ndjson = '$_validHeader\n{"kind":"bogus","data":{}}';

      expect(
        () => reader.parse(ndjson),
        throwsA(
          isA<InvalidLine>().having((e) => e.lineNumber, 'lineNumber', 2),
        ),
      );
    });

    test('a missing data field names its line number', () {
      final ndjson = '$_validHeader\n{"kind":"account"}';

      expect(
        () => reader.parse(ndjson),
        throwsA(
          isA<InvalidLine>().having((e) => e.lineNumber, 'lineNumber', 2),
        ),
      );
    });

    test('a data field with the wrong shape names its line number', () {
      final ndjson = '$_validHeader\n{"kind":"account","data":"not a map"}';

      expect(
        () => reader.parse(ndjson),
        throwsA(
          isA<InvalidLine>().having((e) => e.lineNumber, 'lineNumber', 2),
        ),
      );
    });

    test('a truncated event line is rejected on its own line number', () {
      final header =
          '{"kind":"header","format":1,"app":"cuentaria",'
          '"exportedAt":"2026-01-01T00:00:00.000Z",'
          '"counts":{"event":1,"account":0,"envelope":0,"cascade":0,"rate":0}}';
      final ndjson =
          '$header\n{"kind":"account","data":{"id":"a"}}\n'
          '{"kind":"event","data":{"event_id":"e1","type":"Inc'; // cut mid-line

      expect(
        () => reader.parse(ndjson),
        throwsA(
          isA<InvalidLine>()
              .having((e) => e.lineNumber, 'lineNumber', 3)
              .having((e) => e.reason, 'reason', 'está incompleto'),
        ),
      );
    });

    test('a count mismatch against the header is rejected as truncated', () {
      final header =
          '{"kind":"header","format":1,"app":"cuentaria",'
          '"exportedAt":"2026-01-01T00:00:00.000Z",'
          '"counts":{"event":0,"account":2,"envelope":0,"cascade":0,"rate":0}}';
      final ndjson = '$header\n{"kind":"account","data":{"id":"a"}}';

      expect(() => reader.parse(ndjson), throwsA(isA<TruncatedFile>()));
    });

    test('a well-formed file with matching counts parses successfully', () {
      final ndjson = '$_validHeader\n{"kind":"account","data":{"id":"a"}}';

      final file = reader.parse(ndjson);

      expect(
        file.accounts,
        equals([
          {'id': 'a'},
        ]),
      );
    });

    test('event lines keep their 1-indexed source line number', () {
      final header =
          '{"kind":"header","format":1,"app":"cuentaria",'
          '"exportedAt":"2026-01-01T00:00:00.000Z",'
          '"counts":{"event":2,"account":0,"envelope":0,"cascade":0,"rate":0}}';
      final ndjson =
          '$header\n'
          '{"kind":"event","data":{"event_id":"e1"}}\n'
          '{"kind":"event","data":{"event_id":"e2"}}';

      final file = reader.parse(ndjson);

      expect(file.eventLineNumbers, equals([2, 3]));
    });
  });
}
