import 'package:cuentaria_app/providers/visibility_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('starts hidden by default (#333)', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(balancesHiddenProvider), isTrue);
  });

  test('toggle flips the state', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(balancesHiddenProvider.notifier).toggle();
    expect(container.read(balancesHiddenProvider), isFalse);

    container.read(balancesHiddenProvider.notifier).toggle();
    expect(container.read(balancesHiddenProvider), isTrue);
  });

  test('show() reveals and hide() hides regardless of current state', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(balancesHiddenProvider.notifier).show();
    expect(container.read(balancesHiddenProvider), isFalse);

    container.read(balancesHiddenProvider.notifier).show();
    expect(container.read(balancesHiddenProvider), isFalse);

    container.read(balancesHiddenProvider.notifier).hide();
    expect(container.read(balancesHiddenProvider), isTrue);

    container.read(balancesHiddenProvider.notifier).hide();
    expect(container.read(balancesHiddenProvider), isTrue);
  });
}
