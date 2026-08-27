import 'dart:async';

import 'package:contabilidad/domain/transaction.dart';
import 'package:event_bus/event_bus.dart';

/// Automatic triggers for `CloudCopyUseCase.sync` (issue #224, ADR-0023 §4):
/// once on [start] (app launch), again on every [onResume] (back to
/// foreground), and after each burst of [Transaction] events on the
/// [EventBus] — a burst is coalesced behind [debounce] into a single `sync`
/// call, restarting the wait on every new Transaction. `sync` is never
/// awaited from the event-bus callback, so a slow or failed run never delays
/// the capture flow that published the Transaction; overlap and the
/// disconnected case are handled by `sync` itself
/// (`CloudCopyUseCase.sync`'s own queueing and `isConnected` check) — this
/// class only decides *when* to call it. The app being closed is not
/// covered: there is no scheduler here, see the feature README.
class CloudCopyTriggers {
  final Future<void> Function() sync;
  final EventBus eventBus;
  final Duration debounce;

  StreamSubscription<DomainEvent>? _subscription;
  Timer? _timer;

  CloudCopyTriggers({
    required this.sync,
    required this.eventBus,
    this.debounce = const Duration(seconds: 30),
  });

  /// Starts listening for Transaction events and fires the app-launch sync.
  /// Call once from the composition root, after hydrating the use case.
  void start() {
    _subscription ??= eventBus.stream.listen(_onEvent);
    sync();
  }

  /// Foreground-resume trigger — wire to the app's lifecycle listener.
  void onResume() {
    sync();
  }

  void _onEvent(DomainEvent event) {
    if (event is! Transaction) return;
    _timer?.cancel();
    _timer = Timer(debounce, sync);
  }

  /// Stops listening and cancels any pending debounced sync.
  void dispose() {
    _timer?.cancel();
    _subscription?.cancel();
  }
}
