import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:cuentaria_app/providers/rate_sync_providers.dart';
import 'package:cuentaria_app/providers/tasas_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasas/domain/rate_feed.dart';
import 'package:tasas/domain/rate_observation.dart';

class _CountingRateFeed implements RateFeed {
  int fetchCount = 0;

  @override
  Future<List<RateObservation>> fetch() async {
    fetchCount++;
    return [];
  }
}

void main() {
  testWidgets('reading the trigger fires a sync, and again on app resume', (
    tester,
  ) async {
    final feed = _CountingRateFeed();
    final container = ProviderContainer(
      overrides: [
        isWebProvider.overrideWithValue(true),
        rateFeedProvider.overrideWithValue(feed),
      ],
    );
    addTearDown(container.dispose);

    container.read(rateSyncTriggerProvider);
    await tester.pump();

    expect(feed.fetchCount, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(feed.fetchCount, 2);
  });
}
