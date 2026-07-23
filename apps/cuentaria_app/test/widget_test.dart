import 'package:cuentaria_app/main.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:cuentaria_app/ui/ledger_screen.dart';
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
      // Build our app and trigger a frame. Force the web (in-memory) adapter
      // path — there's no platform channel to open a real encrypted DB here.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [isWebProvider.overrideWithValue(true)],
          child: const MyApp(),
        ),
      );
      await tester.pumpAndSettle(); // Wait for bootstrap + navigation.

      // Verify that the LedgerScreen is rendered.
      expect(find.byType(LedgerScreen), findsOneWidget);
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
