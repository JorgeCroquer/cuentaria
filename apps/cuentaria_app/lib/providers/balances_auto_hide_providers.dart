import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'visibility_providers.dart';

/// The wall clock [balancesAutoHideTriggerProvider] measures background time
/// with — overridden in tests with a fake clock.
final nowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Re-hides balances after returning from >=60s in the background (#333):
/// a quick glance away keeps them visible for the rest of the session, a
/// real backgrounding doesn't. Mirrors `rateSyncTriggerProvider`'s
/// `AppLifecycleListener` wiring — reading this provider is the only
/// trigger.
final balancesAutoHideTriggerProvider = Provider<AppLifecycleListener>((ref) {
  final now = ref.read(nowProvider);
  DateTime? pausedAt;

  final listener = AppLifecycleListener(
    onPause: () => pausedAt = now(),
    onResume: () {
      final since = pausedAt;
      pausedAt = null;
      if (since != null &&
          now().difference(since) >= const Duration(seconds: 60)) {
        ref.read(balancesHiddenProvider.notifier).hide();
      }
    },
  );
  ref.onDispose(listener.dispose);
  return listener;
});
