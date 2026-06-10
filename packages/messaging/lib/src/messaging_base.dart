import 'dart:async';

abstract class DomainEvent {
  const DomainEvent();
}

abstract class EventBus {
  void publish(DomainEvent event);
  Stream<DomainEvent> get stream;
}

class SyncEventBus implements EventBus {
  // A simple synchronous event bus using a StreamController.
  // In a real app, this might be more sophisticated.
  final _controller = StreamController<DomainEvent>.broadcast(sync: true);

  @override
  void publish(DomainEvent event) {
    _controller.add(event);
  }

  @override
  Stream<DomainEvent> get stream => _controller.stream;
  
  void dispose() {
    _controller.close();
  }
}
