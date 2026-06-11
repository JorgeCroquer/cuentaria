import 'package:messaging/messaging.dart';
import 'package:test/test.dart';

class OrderPlacedEvent extends DomainEvent {
  final String orderId;
  const OrderPlacedEvent(this.orderId);
}

class DummyPublisher {
  final EventBus _eventBus;

  DummyPublisher(this._eventBus);

  void checkout(String orderId) {
    _eventBus.publish(OrderPlacedEvent(orderId));
  }
}

class DummySubscriber {
  final EventBus _eventBus;
  int processedOrders = 0;
  String? lastProcessedOrderId;

  DummySubscriber(this._eventBus) {
    _eventBus.stream.listen((event) {
      if (event is OrderPlacedEvent) {
        processedOrders++;
        lastProcessedOrderId = event.orderId;
      }
    });
  }
}

void main() {
  group('EventBus Seam Integration', () {
    test('publisher and subscriber communicate solely through EventBus', () {
      final eventBus = SyncEventBus();
      final publisher = DummyPublisher(eventBus);
      final subscriber = DummySubscriber(eventBus);

      expect(subscriber.processedOrders, equals(0));

      publisher.checkout('ORDER-123');

      expect(subscriber.processedOrders, equals(1));
      expect(subscriber.lastProcessedOrderId, equals('ORDER-123'));
    });
  });
}
