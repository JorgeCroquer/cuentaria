import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether money figures are masked everywhere in the app (#333): a single
/// global eye toggle in Patrimonio's header, hidden by default on every cold
/// start and not persisted — opening the app in public never shows a
/// balance.
class BalancesHiddenNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void toggle() => state = !state;

  void show() => state = false;

  void hide() => state = true;
}

final balancesHiddenProvider = NotifierProvider<BalancesHiddenNotifier, bool>(
  BalancesHiddenNotifier.new,
);
