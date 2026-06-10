import 'package:test/test.dart';
import 'package:shared_kernel/shared_kernel.dart';

void main() {
  group('Strongly-typed IDs', () {
    test('AccountId equates by value and throws on empty', () {
      final id1 = AccountId('acc-123');
      final id2 = AccountId('acc-123');
      final id3 = AccountId('acc-456');

      expect(id1, equals(id2));
      expect(id1, isNot(equals(id3)));
      expect(() => AccountId(''), throwsArgumentError);
    });

    test('EnvelopeId equates by value and throws on empty', () {
      final id1 = EnvelopeId('env-123');
      final id2 = EnvelopeId('env-123');
      final id3 = EnvelopeId('env-456');

      expect(id1, equals(id2));
      expect(id1, isNot(equals(id3)));
      expect(() => EnvelopeId(''), throwsArgumentError);
    });

    test('EventId equates by value and throws on empty', () {
      final id1 = EventId('evt-123');
      final id2 = EventId('evt-123');
      final id3 = EventId('evt-456');

      expect(id1, equals(id2));
      expect(id1, isNot(equals(id3)));
      expect(() => EventId(''), throwsArgumentError);
    });
  });
}
