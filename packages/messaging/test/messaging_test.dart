import 'package:messaging/messaging.dart';
import 'package:test/test.dart';

void main() {
  group('SyncEventBus', () {
    final eventBus = SyncEventBus();

    setUp(() {
      // Additional setup goes here.
    });

    test('exposes a stream of DomainEvents', () {
      expect(eventBus.stream, isA<Stream<DomainEvent>>());
    });
  });
}
