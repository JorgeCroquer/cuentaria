import 'package:test/test.dart';
import 'package:shared_kernel/shared_kernel.dart';

void main() {
  group('DomainTimestamp', () {
    test('equates by value', () {
      final now = DateTime.now();
      final ts1 = DomainTimestamp(now);
      final ts2 = DomainTimestamp(now);
      final ts3 = DomainTimestamp(now.add(const Duration(seconds: 1)));

      expect(ts1, equals(ts2));
      expect(ts1, isNot(equals(ts3)));
    });
  });
}
