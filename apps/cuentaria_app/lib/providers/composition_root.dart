import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:event_bus/event_bus.dart';

final eventBusProvider = Provider<EventBus>((ref) {
  final eventBus = SyncEventBus();
  ref.onDispose(eventBus.dispose);
  return eventBus;
});
