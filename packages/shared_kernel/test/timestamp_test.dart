import 'package:test/test.dart';
import 'package:shared_kernel/shared_kernel.dart';

void main() {
  group('DomainTimestamp', () {
    test('equates by value', () {
      final now = DateTime.now().toUtc();
      final ts1 = DomainTimestamp(now);
      final ts2 = DomainTimestamp(now);
      final ts3 = DomainTimestamp(now.add(const Duration(seconds: 1)));

      expect(ts1, equals(ts2));
      expect(ts1, isNot(equals(ts3)));
    });

    test('throws ArgumentError for non-UTC DateTime', () {
      final local = DateTime.now(); // local time, not UTC
      expect(() => DomainTimestamp(local), throwsArgumentError);
    });

    test('accepts UTC DateTime', () {
      final utc = DateTime.now().toUtc();
      final ts = DomainTimestamp(utc);
      expect(ts.value.isUtc, isTrue);
    });
  });
}
