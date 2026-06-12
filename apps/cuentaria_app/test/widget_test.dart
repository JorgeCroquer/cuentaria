import 'package:cuentaria_app/main.dart';
import 'package:cuentaria_app/placeholder_screen.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:event_bus/event_bus.dart';

class FakeEventBus implements EventBus {
  @override
  void publish(DomainEvent event) {}
  @override
  Stream<DomainEvent> get stream => const Stream.empty();
}

void main() {
  testWidgets(
    'DI and Navigation setup: app resolves initial route without crash',
    (WidgetTester tester) async {
      // Build our app and trigger a frame.
      await tester.pumpWidget(const ProviderScope(child: MyApp()));
      await tester.pumpAndSettle(); // Wait for navigation to complete

      // Verify that the PlaceholderScreen is rendered.
      expect(find.byType(PlaceholderScreen), findsOneWidget);
    },
  );

  test('Composition Root wiring: EventBus is resolvable via Riverpod', () {
    // Create a container with default providers
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Verify it resolves to a SyncEventBus by default
    final defaultEventBus = container.read(eventBusProvider);
    expect(defaultEventBus, isA<SyncEventBus>());

    // Verify it can be overridden
    final fakeEventBus = FakeEventBus();
    final overriddenContainer = ProviderContainer(
      overrides: [eventBusProvider.overrideWithValue(fakeEventBus)],
    );
    addTearDown(overriddenContainer.dispose);

    final resolvedEventBus = overriddenContainer.read(eventBusProvider);
    expect(resolvedEventBus, same(fakeEventBus));
  });
}
