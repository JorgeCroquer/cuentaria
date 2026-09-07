import 'package:cuentaria_app/features/patrimonio/application/patrimonio_providers.dart';
import 'package:cuentaria_app/features/patrimonio/ui/screens/patrimonio_screen.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:patrimonio/patrimonio.dart';
import 'package:shared_kernel/shared_kernel.dart';

/// #279 "Héroe y tarjetas" redesign: coverage for the pieces not already
/// exercised by the pre-existing figure/rate/navigation suites — P&L
/// coloring, the Sin asignar card's container and button, negative envelope
/// styling, the Cuentas row's chevron, and the AppBar's 2-actions rule.
void main() {
  ProviderContainer containerWith(PatrimonioSnapshot snapshot) {
    final container = ProviderContainer(
      overrides: [
        isWebProvider.overrideWithValue(true),
        patrimonioSnapshotProvider.overrideWith((ref) async => snapshot),
      ],
    );
    return container;
  }

  PatrimonioSnapshot snapshotWithPnl(int pnlUsdCents) => PatrimonioSnapshot(
    realCostUsdCents: 1000,
    todayValueUsdCents: 1000 + pnlUsdCents,
    unrealizedPnlUsdCents: pnlUsdCents,
    bcvReferenceUsdCents: 1000,
    hasMissingRate: false,
    accountGroups: [
      PatrimonioAccountGroup(
        currency: CurrencyCode('USD'),
        nativeMinorAmount: BigInt.from(100000),
        realCostUsdCents: 1000,
        todayValueUsdCents: 1000 + pnlUsdCents,
        bcvReferenceUsdCents: 1000,
        hasRate: true,
      ),
    ],
    envelopes: const [],
  );

  testWidgets('paints the unrealized P&L in error when negative', (
    tester,
  ) async {
    final container = containerWith(snapshotWithPnl(-500));
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PatrimonioScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final text = tester.widget<Text>(
      find.byKey(const Key('unrealizedPnlAmount')),
    );
    final context = tester.element(
      find.byKey(const Key('unrealizedPnlAmount')),
    );
    expect(text.style?.color, Theme.of(context).colorScheme.error);
  });

  testWidgets('paints the unrealized P&L in primary when positive', (
    tester,
  ) async {
    final container = containerWith(snapshotWithPnl(500));
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PatrimonioScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final text = tester.widget<Text>(
      find.byKey(const Key('unrealizedPnlAmount')),
    );
    final context = tester.element(
      find.byKey(const Key('unrealizedPnlAmount')),
    );
    expect(text.style?.color, Theme.of(context).colorScheme.primary);
  });

  testWidgets(
    'the Sin asignar card sits on secondaryContainer and its Repartir '
    'button navigates to /distribute',
    (tester) async {
      final container = containerWith(
        PatrimonioSnapshot(
          realCostUsdCents: 5000,
          todayValueUsdCents: 5000,
          unrealizedPnlUsdCents: 0,
          bcvReferenceUsdCents: 5000,
          hasMissingRate: false,
          accountGroups: [
            PatrimonioAccountGroup(
              currency: CurrencyCode('USD'),
              nativeMinorAmount: BigInt.from(500000),
              realCostUsdCents: 5000,
              todayValueUsdCents: 5000,
              bcvReferenceUsdCents: 5000,
              hasRate: true,
            ),
          ],
          envelopes: [
            PatrimonioEnvelope(
              id: EnvelopeId('stage'),
              name: 'Stage',
              role: EnvelopeRoleView.stage,
              balanceUsd: 5000,
              target: const NoTargetView(),
              metadata: const NoMetadata(),
            ),
          ],
        ),
      );
      addTearDown(container.dispose);

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const PatrimonioScreen(),
          ),
          GoRoute(
            path: '/distribute',
            builder:
                (context, state) =>
                    const Scaffold(body: Text('Distribute Screen')),
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

      final cardFinder = find.ancestor(
        of: find.byKey(const Key('repartirButton')),
        matching: find.byType(Card),
      );
      expect(cardFinder, findsOneWidget);
      final card = tester.widget<Card>(cardFinder);
      final context = tester.element(cardFinder);
      expect(card.color, Theme.of(context).colorScheme.secondaryContainer);

      await tester.tap(find.byKey(const Key('repartirButton')));
      await tester.pumpAndSettle();

      expect(find.text('Distribute Screen'), findsOneWidget);
    },
  );

  testWidgets(
    'a negative envelope balance is painted in error with weight 500',
    (tester) async {
      final container = containerWith(
        PatrimonioSnapshot(
          realCostUsdCents: 0,
          todayValueUsdCents: 0,
          unrealizedPnlUsdCents: 0,
          bcvReferenceUsdCents: 0,
          hasMissingRate: false,
          accountGroups: [
            PatrimonioAccountGroup(
              currency: CurrencyCode('USD'),
              nativeMinorAmount: BigInt.zero,
              realCostUsdCents: 0,
              todayValueUsdCents: 0,
              bcvReferenceUsdCents: 0,
              hasRate: true,
            ),
          ],
          envelopes: [
            PatrimonioEnvelope(
              id: EnvelopeId('sobregirado'),
              name: 'Sobregirado',
              role: EnvelopeRoleView.user,
              balanceUsd: -1500,
              target: const NoTargetView(),
              metadata: const NoMetadata(),
            ),
          ],
        ),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: PatrimonioScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final amount = tester.widget<Text>(find.text('\$-15.00'));
      final context = tester.element(find.text('\$-15.00'));
      expect(amount.style?.color, Theme.of(context).colorScheme.error);
      expect(amount.style?.fontWeight, FontWeight.w500);
    },
  );

  testWidgets('the Cuentas row chevron navigates to the Accounts screen', (
    tester,
  ) async {
    final container = containerWith(
      PatrimonioSnapshot(
        realCostUsdCents: 1000,
        todayValueUsdCents: 1000,
        unrealizedPnlUsdCents: 0,
        bcvReferenceUsdCents: 1000,
        hasMissingRate: false,
        accountGroups: [
          PatrimonioAccountGroup(
            currency: CurrencyCode('USD'),
            nativeMinorAmount: BigInt.from(100000),
            realCostUsdCents: 1000,
            todayValueUsdCents: 1000,
            bcvReferenceUsdCents: 1000,
            hasRate: true,
          ),
        ],
        envelopes: const [],
      ),
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const PatrimonioScreen(),
        ),
        GoRoute(
          path: '/accounts',
          builder: (context, state) => const Scaffold(body: Text('Accounts')),
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

    await tester.tap(find.byKey(const Key('accountGroup_USD')));
    await tester.pumpAndSettle();

    expect(find.text('Accounts'), findsOneWidget);
  });

  testWidgets(
    'the AppBar shows exactly Reportes and the overflow menu as visible '
    'actions — every other action moves inside the ⋮ (#279)',
    (tester) async {
      final container = containerWith(
        PatrimonioSnapshot(
          realCostUsdCents: 1000,
          todayValueUsdCents: 1000,
          unrealizedPnlUsdCents: 0,
          bcvReferenceUsdCents: 1000,
          hasMissingRate: false,
          accountGroups: [
            PatrimonioAccountGroup(
              currency: CurrencyCode('USD'),
              nativeMinorAmount: BigInt.from(100000),
              realCostUsdCents: 1000,
              todayValueUsdCents: 1000,
              bcvReferenceUsdCents: 1000,
              hasRate: true,
            ),
          ],
          envelopes: const [],
        ),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: PatrimonioScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.actions, hasLength(2));
      expect(find.byKey(const Key('reportsAction')), findsOneWidget);
      expect(find.byKey(const Key('patrimonioOverflowMenu')), findsOneWidget);
      expect(find.byKey(const Key('manageAccountsAction')), findsNothing);
      expect(find.byKey(const Key('manageEnvelopesAction')), findsNothing);
      expect(find.byKey(const Key('editCascadeAction')), findsNothing);
      expect(find.byKey(const Key('recordRatesAction')), findsNothing);

      await tester.tap(find.byKey(const Key('patrimonioOverflowMenu')));
      await tester.pumpAndSettle();

      for (final key in const [
        'manageAccountsAction',
        'manageEnvelopesAction',
        'editCascadeAction',
        'recordRatesAction',
        'backupMenuItem',
        'debtsMenuItem',
        'cloudCopyMenuItem',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
    },
  );
}
