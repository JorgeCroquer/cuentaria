import 'package:cuentaria_app/providers/balances_auto_hide_providers.dart';
import 'package:cuentaria_app/providers/visibility_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'returning from background after 10s leaves balances visible (#333)',
    (tester) async {
      var now = DateTime(2026, 1, 1, 12);
      final container = ProviderContainer(
        overrides: [nowProvider.overrideWithValue(() => now)],
      );
      addTearDown(container.dispose);

      container.read(balancesAutoHideTriggerProvider);
      container.read(balancesHiddenProvider.notifier).show();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      now = now.add(const Duration(seconds: 10));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(container.read(balancesHiddenProvider), isFalse);
    },
  );

  testWidgets('returning from background after 60s re-hides balances (#333)', (
    tester,
  ) async {
    var now = DateTime(2026, 1, 1, 12);
    final container = ProviderContainer(
      overrides: [nowProvider.overrideWithValue(() => now)],
    );
    addTearDown(container.dispose);

    container.read(balancesAutoHideTriggerProvider);
    container.read(balancesHiddenProvider.notifier).show();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    now = now.add(const Duration(seconds: 60));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(container.read(balancesHiddenProvider), isTrue);
  });
}
