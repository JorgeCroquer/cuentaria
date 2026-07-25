import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/catalog/models/funding_target.dart';
import 'package:cuentaria_app/features/envelopes/ui/screens/envelope_edit_screen.dart';
import 'package:cuentaria_app/features/envelopes/ui/screens/envelopes_list_screen.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_kernel/shared_kernel.dart';

Future<GoRouter> _pumpApp(
  WidgetTester tester,
  ProviderContainer container,
) async {
  final router = GoRouter(
    initialLocation: '/envelopes',
    routes: [
      GoRoute(
        path: '/envelopes',
        builder: (context, state) => const EnvelopesListScreen(),
      ),
      GoRoute(
        path: '/envelopes/new',
        builder: (context, state) => const EnvelopeEditScreen(),
      ),
      GoRoute(
        path: '/envelopes/:id/edit',
        builder:
            (context, state) => EnvelopeEditScreen(
              envelopeId: EnvelopeId(state.pathParameters['id']!),
            ),
      ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('lists only user envelopes, never system ones (#95)', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [isWebProvider.overrideWithValue(true)],
    );
    addTearDown(container.dispose);

    final catalog = await container.read(catalogRepositoryProvider.future);
    await catalog.saveEnvelope(
      Envelope(
        id: EnvelopeId('mercado'),
        name: 'Mercado',
        role: EnvelopeRole.none,
        isArchived: false,
        updatedAt: DateTime.now(),
      ),
    );

    await _pumpApp(tester, container);

    expect(find.text('Mercado'), findsOneWidget);
    expect(find.text('Stage'), findsNothing);
    expect(find.text('Differential'), findsNothing);
    expect(find.text('Adjustments'), findsNothing);
    expect(find.text('Opening'), findsNothing);
  });

  testWidgets('hides archived envelopes', (tester) async {
    final container = ProviderContainer(
      overrides: [isWebProvider.overrideWithValue(true)],
    );
    addTearDown(container.dispose);

    final catalog = await container.read(catalogRepositoryProvider.future);
    await catalog.saveEnvelope(
      Envelope(
        id: EnvelopeId('viejo'),
        name: 'Viejo',
        role: EnvelopeRole.none,
        isArchived: true,
        updatedAt: DateTime.now(),
      ),
    );

    await _pumpApp(tester, container);

    expect(find.text('Viejo'), findsNothing);
  });

  testWidgets('archiving an envelope removes it from the list', (tester) async {
    final container = ProviderContainer(
      overrides: [isWebProvider.overrideWithValue(true)],
    );
    addTearDown(container.dispose);

    final catalog = await container.read(catalogRepositoryProvider.future);
    await catalog.saveEnvelope(
      Envelope(
        id: EnvelopeId('mercado'),
        name: 'Mercado',
        role: EnvelopeRole.none,
        isArchived: false,
        updatedAt: DateTime.now(),
      ),
    );

    await _pumpApp(tester, container);
    expect(find.text('Mercado'), findsOneWidget);

    await tester.tap(find.byKey(const Key('archiveEnvelope_mercado')));
    await tester.pumpAndSettle();

    expect(find.text('Mercado'), findsNothing);
    final stored = catalog.getEnvelope(EnvelopeId('mercado'));
    expect(stored!.isArchived, isTrue);
  });

  testWidgets('the FAB navigates to the create screen', (tester) async {
    final container = ProviderContainer(
      overrides: [isWebProvider.overrideWithValue(true)],
    );
    addTearDown(container.dispose);

    await _pumpApp(tester, container);

    await tester.tap(find.byKey(const Key('createEnvelopeButton')));
    await tester.pumpAndSettle();

    expect(find.byType(EnvelopeEditScreen), findsOneWidget);
  });

  testWidgets('tapping an envelope navigates to its edit screen', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [isWebProvider.overrideWithValue(true)],
    );
    addTearDown(container.dispose);

    final catalog = await container.read(catalogRepositoryProvider.future);
    await catalog.saveEnvelope(
      Envelope(
        id: EnvelopeId('mercado'),
        name: 'Mercado',
        role: EnvelopeRole.none,
        isArchived: false,
        updatedAt: DateTime.now(),
      ).withTarget(const Cap(amountUsd: 30000)),
    );

    await _pumpApp(tester, container);

    await tester.tap(find.text('Mercado'));
    await tester.pumpAndSettle();

    expect(find.byType(EnvelopeEditScreen), findsOneWidget);
    final nameField = tester.widget<TextFormField>(
      find.byKey(const Key('nameField')),
    );
    expect(nameField.controller!.text, 'Mercado');
  });
}
