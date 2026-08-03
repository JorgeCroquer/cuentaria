import 'package:contabilidad/application/cascade/cascade.dart';
import 'package:contabilidad/application/cascade/cascade_step.dart';
import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:cuentaria_app/features/distribution/ui/screens/cascade_editor_screen.dart';
import 'package:cuentaria_app/features/patrimonio/ui/screens/patrimonio_screen.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_kernel/shared_kernel.dart';

void main() {
  testWidgets(
    'cascade editor is reachable from Patrimonio via AppBar even with zero '
    'Stage balance (#111)',
    (tester) async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      final catalog = await container.read(catalogRepositoryProvider.future);

      // Create account and envelope
      final accountId = AccountId('test-acc');
      await catalog.saveAccount(
        Account(
          id: accountId,
          name: 'Test Account',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      final ahorros = EnvelopeId('ahorros');
      await catalog.saveEnvelope(
        Envelope(
          id: ahorros,
          name: 'Ahorros',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      final cascadeRepo = await container.read(
        cascadeRepositoryProvider.future,
      );
      await cascadeRepo.save(
        Cascade(
          steps: [CascadeStep.catchAll(envelopeId: ahorros)],
          updatedAt: DateTime.now(),
        ),
      );

      // Setup router with cascade editor route
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const PatrimonioScreen(),
          ),
          GoRoute(
            path: '/distribute/edit',
            builder: (context, state) => const CascadeEditorScreen(),
          ),
          GoRoute(
            path: '/accounts',
            builder:
                (context, state) =>
                    const Scaffold(body: Text('Accounts Screen')),
          ),
          GoRoute(
            path: '/envelopes',
            builder:
                (context, state) =>
                    const Scaffold(body: Text('Envelopes Screen')),
          ),
        ],
      );

      // Build app with NO pending Stage balance (cold start)
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      // Verify: Stage row is not visible (zero balance hidden by engine)
      expect(
        find.text('Sin asignar'),
        findsNothing,
        reason: 'Stage row should not render with zero balance',
      );

      // Verify: AppBar actions are all visible
      expect(find.byKey(const Key('manageAccountsAction')), findsOneWidget);
      expect(find.byKey(const Key('manageEnvelopesAction')), findsOneWidget);
      expect(find.byKey(const Key('editCascadeAction')), findsOneWidget);
      expect(find.byKey(const Key('recordRatesAction')), findsOneWidget);

      // Click the edit cascade action in AppBar
      await tester.tap(find.byKey(const Key('editCascadeAction')));
      await tester.pumpAndSettle();

      // Verify: navigated to cascade editor
      expect(
        find.byType(CascadeEditorScreen),
        findsOneWidget,
        reason:
            'Should navigate to cascade editor even with zero pending balance',
      );
    },
  );
}
