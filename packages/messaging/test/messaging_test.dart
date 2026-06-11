import 'package:messaging/messaging.dart';
import 'package:test/test.dart';

class DummyEvent extends DomainEvent {
  final String payload;
  const DummyEvent(this.payload);
}

void main() {
  group('SyncEventBus', () {
    late SyncEventBus eventBus;

    setUp(() {
      eventBus = SyncEventBus();
    });

    tearDown(() {
      eventBus.dispose();
    });

    test('exposes a stream of DomainEvents', () {
      expect(eventBus.stream, isA<Stream<DomainEvent>>());
    });

    test('delivers published event to a single subscriber', () async {
      final event = DummyEvent('test_payload');
      DomainEvent? receivedEvent;

      eventBus.stream.listen((e) {
        receivedEvent = e;
      });

      eventBus.publish(event);

      expect(receivedEvent, isNotNull);
      expect((receivedEvent as DummyEvent).payload, equals('test_payload'));
    });

    test('delivers published event to multiple subscribers', () async {
      final event = DummyEvent('broadcast_payload');
      int receivedCount = 0;

      eventBus.stream.listen((_) => receivedCount++);
      eventBus.stream.listen((_) => receivedCount++);
      eventBus.stream.listen((_) => receivedCount++);

      eventBus.publish(event);

      expect(receivedCount, equals(3));
    });

    test('dispatches events synchronously before publish returns', () {
      final event = DummyEvent('sync_payload');
      final executionOrder = <String>[];

      eventBus.stream.listen((_) {
        executionOrder.add('subscriber_received');
      });

      executionOrder.add('before_publish');
      eventBus.publish(event);
      executionOrder.add('after_publish');

      expect(
        executionOrder,
        equals(['before_publish', 'subscriber_received', 'after_publish']),
      );
    });
  });
}
