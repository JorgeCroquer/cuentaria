import 'dart:async';

abstract class DomainEvent {
  const DomainEvent();
}

abstract class EventBus {
  void publish(DomainEvent event);
  Stream<DomainEvent> get stream;
}

/// In-process, synchronous [EventBus].
///
/// Backed by a broadcast [StreamController]: events are delivered only to
/// subscribers that are already listening at `publish` time — there is no
/// buffering or replay. Subscription ordering at the composition root is
/// therefore load-bearing. `dispose()` is intentionally not on the [EventBus]
/// port; only the lifecycle owner (the composition root) closes the bus.
class SyncEventBus implements EventBus {
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
