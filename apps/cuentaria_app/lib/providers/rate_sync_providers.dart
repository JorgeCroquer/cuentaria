import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/debts/application/debts_providers.dart';
import '../features/patrimonio/application/patrimonio_providers.dart';
import 'tasas_providers.dart';

/// Fires [SyncRateSeriesUseCase] when the app opens and every time it
/// returns from the background (S2, ADR-0020 §6) — reading this provider is
/// the only trigger; nothing in the capture path touches it, so a slow or
/// failed sync never blocks registering a movement. If the sync finishes
/// after a screen already painted, invalidating these providers refreshes
/// it on its own; a network hiccup stays invisible since the use case
/// fails silent.
final rateSyncTriggerProvider = Provider<AppLifecycleListener>((ref) {
  Future<void> sync() async {
    final useCase = await ref.read(syncRateSeriesUseCaseProvider.future);
    await useCase.sync();
    ref.invalidate(patrimonioSnapshotProvider);
    ref.invalidate(debtsSnapshotProvider);
    ref.invalidate(latestParaleloRateProvider);
    ref.invalidate(latestOficialRateProvider);
  }

  final listener = AppLifecycleListener(onResume: sync);
  ref.onDispose(listener.dispose);
  sync();
  return listener;
});
