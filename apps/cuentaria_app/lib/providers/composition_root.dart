import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:messaging/messaging.dart';

final eventBusProvider = Provider<EventBus>((ref) {
  final eventBus = SyncEventBus();
  ref.onDispose(eventBus.dispose);
  return eventBus;
});
