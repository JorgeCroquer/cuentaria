import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/ledger/factories/record_usd_expense.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:cuentaria_app/ui/screens/movements/movement_detail_screen.dart';
import 'package:cuentaria_app/ui/screens/movements/movements_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_kernel/shared_kernel.dart';

/// #333: balances hidden by default means Movimientos' list and detail
/// screens show no digit in their amounts either.
void main() {
  testWidgets(
    'shows no digit in the list row or the detail posting while hidden '
    '(#333)',
    (tester) async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      final catalog = await container.read(catalogRepositoryProvider.future);
      final accountId = AccountId('acc-1');
      await catalog.saveAccount(
        Account(
          id: accountId,
          name: 'Efectivo',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );
      final envelopeId = EnvelopeId('comida');
      await catalog.saveEnvelope(
        Envelope(
          id: envelopeId,
          name: 'Comida',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: DateTime.now(),
        ),
      );

      final store = await container.read(eventStoreProvider.future);
      final projections = container.read(ledgerProjectionsProvider);
      final eventBus = container.read(eventBusProvider);
      final deviceId = await container.read(deviceIdProvider.future);
      final recordUsdExpense = RecordUsdExpense(
        record: RecordTransaction(
          store: store,
          projections: projections,
          eventBus: eventBus,
          validator: ReferentialIntegrityValidator(catalog),
        ),
        catalog: catalog,
      );
      final eventId = EventId('evt-hide-1');
      await recordUsdExpense(
        eventId: eventId,
        deviceId: deviceId,
        accountId: accountId,
        envelopeId: envelopeId,
        amount: Money(amount: BigInt.from(1200), currency: CurrencyCode('USD')),
        memo: 'Comida',
      );

      final router = GoRouter(
        initialLocation: '/movements',
        routes: [
          GoRoute(
            path: '/movements',
            builder: (context, state) => const MovementsScreen(),
          ),
          GoRoute(
            path: '/movements/:id',
            builder:
                (context, state) => MovementDetailScreen(
                  eventId: EventId(state.pathParameters['id']!),
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

      final listTexts = tester
          .widgetList<Text>(find.textContaining('••••'))
          .map((t) => t.data!);
      expect(listTexts, isNotEmpty);
      expect(listTexts.any((t) => RegExp(r'\d').hasMatch(t)), isFalse);

      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();

      expect(find.byType(MovementDetailScreen), findsOneWidget);
      final detailTexts = tester
          .widgetList<Text>(find.textContaining('••••'))
          .map((t) => t.data!);
      expect(detailTexts, isNotEmpty);
      expect(detailTexts.any((t) => RegExp(r'\d').hasMatch(t)), isFalse);
    },
  );
}
