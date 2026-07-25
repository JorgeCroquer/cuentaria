import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/catalog/models/envelope_appearance.dart';
import 'package:contabilidad/application/catalog/models/funding_target.dart';
import 'package:cuentaria_app/features/envelopes/ui/screens/envelope_edit_screen.dart';
import 'package:cuentaria_app/features/envelopes/ui/screens/envelopes_list_screen.dart';
import 'package:cuentaria_app/features/patrimonio/application/patrimonio_providers.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_kernel/shared_kernel.dart';

Future<GoRouter> _pumpApp(
  WidgetTester tester,
  ProviderContainer container, {
  String pushLocation = '/envelopes/new',
}) async {
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
  router.push(pushLocation);
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('creating a Cap envelope saves it and returns to the list', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [isWebProvider.overrideWithValue(true)],
    );
    addTearDown(container.dispose);

    await _pumpApp(tester, container);

    await tester.enterText(find.byKey(const Key('nameField')), 'Mercado');
    await tester.tap(find.byKey(const Key('icon_shopping_cart')));
    await tester.tap(find.byKey(const Key('color_2')));

    await tester.tap(find.byKey(const Key('targetKindDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cap').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('targetAmountField')), '300');

    await tester.tap(find.byKey(const Key('saveEnvelopeButton')));
    await tester.pumpAndSettle();

    expect(find.byType(EnvelopesListScreen), findsOneWidget);

    final catalog = await container.read(catalogRepositoryProvider.future);
    final saved = catalog.envelopes.singleWhere(
      (e) => e.name == 'Mercado' && e.role == EnvelopeRole.none,
    );
    expect(saved.target, const Cap(amountUsd: 30000));
    expect(
      saved.appearance,
      const EnvelopeAppearance(iconId: 'shopping_cart', colorIndex: 2),
    );
  });

  testWidgets('creating a GoalLine envelope with a due date', (tester) async {
    final container = ProviderContainer(
      overrides: [isWebProvider.overrideWithValue(true)],
    );
    addTearDown(container.dispose);

    await _pumpApp(tester, container);

    await tester.enterText(find.byKey(const Key('nameField')), 'Mudanza');

    await tester.tap(find.byKey(const Key('targetKindDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Goal line').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('targetAmountField')), '1000');

    await tester.tap(find.byKey(const Key('saveEnvelopeButton')));
    await tester.pumpAndSettle();

    final catalog = await container.read(catalogRepositoryProvider.future);
    final saved = catalog.envelopes.singleWhere((e) => e.name == 'Mudanza');
    expect(saved.target, isA<GoalLine>());
    expect((saved.target as GoalLine).amountUsd, 100000);
  });

  testWidgets('name is required to save', (tester) async {
    final container = ProviderContainer(
      overrides: [isWebProvider.overrideWithValue(true)],
    );
    addTearDown(container.dispose);

    await _pumpApp(tester, container);

    await tester.tap(find.byKey(const Key('saveEnvelopeButton')));
    await tester.pumpAndSettle();

    expect(find.byType(EnvelopeEditScreen), findsOneWidget);
    final catalog = await container.read(catalogRepositoryProvider.future);
    expect(
      catalog.envelopes.where((e) => e.role == EnvelopeRole.none),
      isEmpty,
    );
  });

  testWidgets(
    'deep-linking to a system envelope does not expose an editable form',
    (tester) async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      final catalog = await container.read(catalogRepositoryProvider.future);
      final stageId = catalog.getSystemEnvelope(EnvelopeRole.stage);
      final before = catalog.getEnvelope(stageId)!;

      await _pumpApp(
        tester,
        container,
        pushLocation: '/envelopes/${stageId.value}/edit',
      );

      expect(find.byKey(const Key('systemEnvelopeNotice')), findsOneWidget);
      expect(find.byKey(const Key('nameField')), findsNothing);
      expect(find.byKey(const Key('saveEnvelopeButton')), findsNothing);

      final after = catalog.getEnvelope(stageId)!;
      expect(after.name, before.name);
      expect(after.meta, before.meta);
    },
  );

  testWidgets('editing an existing envelope pre-fills and updates it', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [isWebProvider.overrideWithValue(true)],
    );
    addTearDown(container.dispose);

    final catalog = await container.read(catalogRepositoryProvider.future);
    final id = EnvelopeId('mercado');
    await catalog.saveEnvelope(
      Envelope(
            id: id,
            name: 'Mercado',
            role: EnvelopeRole.none,
            isArchived: false,
            updatedAt: DateTime.now(),
          )
          .withTarget(const Cap(amountUsd: 30000))
          .withAppearance(
            const EnvelopeAppearance(iconId: 'shopping_cart', colorIndex: 2),
          ),
    );

    await _pumpApp(tester, container, pushLocation: '/envelopes/mercado/edit');

    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('nameField')))
          .controller!
          .text,
      'Mercado',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('targetAmountField')))
          .controller!
          .text,
      '300.00',
    );

    await tester.enterText(find.byKey(const Key('nameField')), 'Super');
    await tester.tap(find.byKey(const Key('saveEnvelopeButton')));
    await tester.pumpAndSettle();

    final updated = catalog.getEnvelope(id)!;
    expect(updated.name, 'Super');
    expect(updated.target, const Cap(amountUsd: 30000));
    expect(
      updated.appearance,
      const EnvelopeAppearance(iconId: 'shopping_cart', colorIndex: 2),
    );
  });

  testWidgets('editing target, icon and color updates reactively', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [isWebProvider.overrideWithValue(true)],
    );
    addTearDown(container.dispose);

    final catalog = await container.read(catalogRepositoryProvider.future);
    final id = EnvelopeId('mercado');
    await catalog.saveEnvelope(
      Envelope(
            id: id,
            name: 'Mercado',
            role: EnvelopeRole.none,
            isArchived: false,
            updatedAt: DateTime.now(),
          )
          .withTarget(const Cap(amountUsd: 30000))
          .withAppearance(
            const EnvelopeAppearance(iconId: 'shopping_cart', colorIndex: 2),
          ),
    );

    await _pumpApp(tester, container, pushLocation: '/envelopes/mercado/edit');

    await tester.tap(find.byKey(const Key('icon_home')));
    await tester.tap(find.byKey(const Key('color_5')));

    await tester.tap(find.byKey(const Key('targetKindDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Goal line').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('targetAmountField')), '1000');

    await tester.tap(find.byKey(const Key('saveEnvelopeButton')));
    await tester.pumpAndSettle();

    final updated = catalog.getEnvelope(id)!;
    expect(updated.name, 'Mercado');
    expect(updated.target, isA<GoalLine>());
    expect((updated.target as GoalLine).amountUsd, 100000);
    expect(
      updated.appearance,
      const EnvelopeAppearance(iconId: 'home', colorIndex: 5),
    );

    final snapshot = await container.read(patrimonioSnapshotProvider.future);
    final envelopeView = snapshot.envelopes.singleWhere((e) => e.id == id);
    expect(envelopeView.iconId, 'home');
    expect(envelopeView.colorIndex, 5);
  });
}
