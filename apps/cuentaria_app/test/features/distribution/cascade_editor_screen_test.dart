import 'package:contabilidad/application/cascade/cascade_step.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:cuentaria_app/features/distribution/ui/screens/cascade_editor_screen.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_kernel/shared_kernel.dart';

Future<ProviderContainer> _seedEnvelopes(List<String> names) async {
  final container = ProviderContainer(
    overrides: [isWebProvider.overrideWithValue(true)],
  );
  final catalog = await container.read(catalogRepositoryProvider.future);
  for (final name in names) {
    await catalog.saveEnvelope(
      Envelope(
        id: EnvelopeId(name),
        name: name,
        role: EnvelopeRole.none,
        isArchived: false,
        updatedAt: DateTime.now(),
      ),
    );
  }
  return container;
}

/// Mirrors the real router: a placeholder home route plus `/distribute/edit`,
/// so [CascadeEditorScreen]'s `context.pop()` on save has somewhere to
/// return to (as it always does when reached from the real app).
Future<GoRouter> _pumpEditor(
  WidgetTester tester,
  ProviderContainer container,
) async {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SizedBox()),
      GoRoute(
        path: '/distribute/edit',
        builder: (context, state) => const CascadeEditorScreen(),
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
  router.push('/distribute/edit');
  await tester.pumpAndSettle();
  return router;
}

Future<void> _addStep(
  WidgetTester tester, {
  required String envelopeName,
  required String fundingType,
  String? amount,
  String? percent,
}) async {
  await tester.tap(find.byKey(const Key('addCascadeStepButton')));
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('stepEnvelopeDropdown')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(envelopeName).last);
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('stepFundingTypeDropdown')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(fundingType).last);
  await tester.pumpAndSettle();

  if (amount != null) {
    await tester.enterText(find.byKey(const Key('stepAmountField')), amount);
  }
  if (percent != null) {
    await tester.enterText(find.byKey(const Key('stepPercentField')), percent);
  }

  await tester.tap(find.byKey(const Key('saveStepButton')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('cold start with no cascade shows the empty state (#96)', (
    tester,
  ) async {
    final container = await _seedEnvelopes(['Mercado']);
    addTearDown(container.dispose);

    await _pumpEditor(tester, container);

    expect(find.byKey(const Key('cascadeEmptyState')), findsOneWidget);
    expect(find.byKey(const Key('saveCascadeButton')), findsOneWidget);
  });

  testWidgets('builds a 4-step cascade, reorders it and persists it via the '
      'CascadeRepository (#96)', (tester) async {
    final container = await _seedEnvelopes([
      'Mercado',
      'Suscripciones',
      'Mudanza',
      'Ocio',
    ]);
    addTearDown(container.dispose);

    final router = await _pumpEditor(tester, container);

    await _addStep(
      tester,
      envelopeName: 'Mercado',
      fundingType: 'Fixed amount',
      amount: '100',
    );
    await _addStep(
      tester,
      envelopeName: 'Suscripciones',
      fundingType: 'Fill to cap',
    );
    await _addStep(
      tester,
      envelopeName: 'Mudanza',
      fundingType: '% of remainder',
      percent: '50',
    );
    await _addStep(tester, envelopeName: 'Ocio', fundingType: 'Catch-all');

    expect(find.text('Fixed \$100.00 → Mercado'), findsOneWidget);
    expect(find.text('Fill to cap → Suscripciones'), findsOneWidget);
    expect(find.text('50% of remainder → Mudanza'), findsOneWidget);
    expect(find.text('Catch-all → Ocio'), findsOneWidget);
    expect(find.byKey(const Key('cascadeValidationErrors')), findsNothing);

    // Reorder by drag: swap the first two steps (Mercado, Suscripciones),
    // keeping the catch-all last so the cascade stays valid.
    final from = tester.getCenter(find.byKey(const Key('dragHandle_0')));
    final to = tester.getCenter(find.byKey(const Key('cascadeStep_1')));
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 50));
    final steps = 6;
    final delta = (to - from) / steps.toDouble();
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(delta);
      await tester.pump(const Duration(milliseconds: 20));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      tester.widgetList<ListTile>(find.byType(ListTile)).first.title,
      isA<Text>().having((t) => t.data, 'data', 'Fill to cap → Suscripciones'),
    );
    expect(find.byKey(const Key('cascadeValidationErrors')), findsNothing);

    await tester.tap(find.byKey(const Key('saveCascadeButton')));
    await tester.pumpAndSettle();

    final repo = await container.read(cascadeRepositoryProvider.future);
    final saved = await repo.load();
    expect(saved, isNotNull);
    expect(saved!.steps, hasLength(4));
    expect(saved.steps[0], isA<FillToCapStep>());
    expect((saved.steps[0] as FillToCapStep).envelopeId.value, 'Suscripciones');
    expect(saved.steps[1], isA<FixedStep>());
    expect((saved.steps[1] as FixedStep).amountUsd, 10000);
    expect((saved.steps[1] as FixedStep).envelopeId.value, 'Mercado');
    expect(saved.steps[2], isA<PercentOfRemainderStep>());
    expect(saved.steps[3], isA<CatchAllStep>());
    expect((saved.steps[3] as CatchAllStep).envelopeId.value, 'Ocio');

    // Saving pops back to the caller.
    expect(find.byType(CascadeEditorScreen), findsNothing);

    // Re-opening the editor (a fresh widget/state, as a real restart would
    // give) reloads from the repository rather than any leftover widget
    // state — the edits survive.
    router.push('/distribute/edit');
    await tester.pumpAndSettle();

    expect(find.text('Fixed \$100.00 → Mercado'), findsOneWidget);
    expect(find.text('Fill to cap → Suscripciones'), findsOneWidget);
    expect(find.text('50% of remainder → Mudanza'), findsOneWidget);
    expect(find.text('Catch-all → Ocio'), findsOneWidget);
    expect(
      tester.widgetList<ListTile>(find.byType(ListTile)).first.title,
      isA<Text>().having((t) => t.data, 'data', 'Fill to cap → Suscripciones'),
    );
  });

  testWidgets(
    'rejects a cascade whose catch-all is not last, with visible feedback '
    '(#96)',
    (tester) async {
      final container = await _seedEnvelopes(['Ahorros', 'Ocio']);
      addTearDown(container.dispose);

      await _pumpEditor(tester, container);

      await _addStep(tester, envelopeName: 'Ocio', fundingType: 'Catch-all');
      await _addStep(
        tester,
        envelopeName: 'Ahorros',
        fundingType: 'Fixed amount',
        amount: '50',
      );

      expect(find.byKey(const Key('cascadeValidationErrors')), findsOneWidget);
      expect(find.textContaining('must be last'), findsOneWidget);

      final saveButton = tester.widget<ElevatedButton>(
        find.byKey(const Key('saveCascadeButton')),
      );
      expect(saveButton.onPressed, isNull);
    },
  );

  testWidgets(
    'rejects a cascade with two catch-all steps, with visible feedback '
    '(#96)',
    (tester) async {
      final container = await _seedEnvelopes(['A', 'B']);
      addTearDown(container.dispose);

      await _pumpEditor(tester, container);

      await _addStep(tester, envelopeName: 'A', fundingType: 'Catch-all');
      await _addStep(tester, envelopeName: 'B', fundingType: 'Catch-all');

      expect(find.byKey(const Key('cascadeValidationErrors')), findsOneWidget);
      expect(find.textContaining('Only one catch-all'), findsOneWidget);

      final saveButton = tester.widget<ElevatedButton>(
        find.byKey(const Key('saveCascadeButton')),
      );
      expect(saveButton.onPressed, isNull);
    },
  );

  testWidgets('a step can be removed from the list (#96)', (tester) async {
    final container = await _seedEnvelopes(['Mercado']);
    addTearDown(container.dispose);

    await _pumpEditor(tester, container);

    await _addStep(tester, envelopeName: 'Mercado', fundingType: 'Catch-all');
    expect(find.text('Catch-all → Mercado'), findsOneWidget);

    await tester.tap(find.byKey(const Key('deleteCascadeStep_0')));
    await tester.pumpAndSettle();

    expect(find.text('Catch-all → Mercado'), findsNothing);
    expect(find.byKey(const Key('cascadeEmptyState')), findsOneWidget);
  });
}
