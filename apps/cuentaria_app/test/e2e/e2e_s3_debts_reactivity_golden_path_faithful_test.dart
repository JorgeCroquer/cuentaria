/// S3 faithful end-to-end test (issue #210, ADR-0022): the golden path that
/// closes S3 — Deudas and Patrimonio's "Deudas" line recompute on every
/// Transaction published through the real EventBus (the S2-7 pattern
/// [patrimonioSnapshotProvider] already used), with no manual reload.
///
/// Golden path: crear Pedro (USD) y prestarle \$200,00 → crear Ana (VES) y
/// prestarle 4 000,00 Bs a tasa 40,00 (se congela \$100,00) → registrar tasa
/// 50,00 (Ana se revaloriza a \$80,00) → conciliar Claudia \$37,00 y luego
/// -\$12,00 (cruce de cero, ADR-0017).
///
/// Drives the real app shell ([MyApp]) with in-memory adapters
/// ([isWebProvider]) and calls the very same application-layer use cases the
/// UI itself calls ([createAccountProvider], the real [RecordRatesDialog]
/// widget, [reconcileUseCaseProvider]) — no mocks, and no manual
/// `ref.invalidate` from the test itself: every figure on screen must update
/// on its own.
library;

import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:cuentaria_app/features/accounts/application/account_providers.dart';
import 'package:cuentaria_app/features/debts/ui/screens/debts_screen.dart';
import 'package:cuentaria_app/features/patrimonio/ui/screens/patrimonio_screen.dart';
import 'package:cuentaria_app/features/reconciliation/application/reconciliation_providers.dart';
import 'package:cuentaria_app/main.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';

/// Patrimonio renders an empty-state guidance screen instead of its body
/// (and never mounts the "Deudas" line) when the catalog has no regular
/// Account — seed one liquid Account so the golden path's Debt Accounts
/// have somewhere to have been lent from.
Future<void> _seedEfectivo(CatalogRepository catalog) async {
  await catalog.saveAccount(
    Account(
      id: AccountId('efectivo'),
      name: 'Efectivo',
      nativeCurrency: CurrencyCode('USD'),
      isArchived: false,
      updatedAt: DateTime.now(),
    ),
  );
}

final _seededCatalogOverride = catalogRepositoryProvider.overrideWith((
  ref,
) async {
  final repository = InMemoryCatalogRepository();
  await _seedEfectivo(repository);
  return repository;
});

void main() {
  testWidgets(
    'crear + prestar Pedro y Ana, registrar tasa, conciliar Claudia con '
    'cruce de cero — Deudas y Patrimonio recomputan sin recargar nada (#210)',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isWebProvider.overrideWithValue(true),
            _seededCatalogOverride,
          ],
          child: const MyApp(),
        ),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(PatrimonioScreen)),
      );
      final deviceId = await container.read(deviceIdProvider.future);
      final createAccount = await container.read(createAccountProvider.future);

      // ---------------------------------------------------------------
      // 1-2. Crear Pedro (USD) y Ana (VES), prestándoles en el mismo acto
      //    a través del saldo de apertura — la misma vía real que usa la
      //    pantalla "Nueva persona". Ana congela \$100,00 a tasa 40,00.
      // ---------------------------------------------------------------
      await createAccount(
        name: 'Pedro',
        nativeCurrency: CurrencyCode('USD'),
        counterpartyName: 'Pedro',
        openingBalance: Money(
          amount: BigInt.from(20000),
          currency: CurrencyCode('USD'),
        ),
        eventId: EventId('evt-crear-pedro'),
        deviceId: deviceId,
      );

      await createAccount(
        name: 'Ana',
        nativeCurrency: CurrencyCode('VES'),
        counterpartyName: 'Ana',
        openingBalance: Money(
          amount: BigInt.from(400000),
          currency: CurrencyCode('VES'),
        ),
        openingBalanceRate: Decimal.parse('40.00'),
        eventId: EventId('evt-crear-ana'),
        deviceId: deviceId,
      );

      // Reactividad por EventBus: sin invalidar nada a mano, Deudas ya
      // muestra ambas personas al navegar hacia la pantalla.
      await tester.tap(find.byKey(const Key('patrimonioOverflowMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('debtsMenuItem')));
      await tester.pumpAndSettle();

      expect(find.byType(DebtsScreen), findsOneWidget);
      expect(find.text('Pedro te debe \$200.00'), findsOneWidget);
      expect(
        find.text('Ana te debe \$100.00'),
        findsOneWidget,
        reason: 'Congelada a tasa 40,00: 4 000,00 Bs / 40,00 = \$100,00',
      );

      // ---------------------------------------------------------------
      // 3. Registrar tasa 50,00 a través del diálogo real de Patrimonio.
      //    Ana debe revalorizarse a \$80,00, en Deudas y en la línea de
      //    Patrimonio, sin tocar nada más que este diálogo.
      // ---------------------------------------------------------------
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('recordRatesAction')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('bcvRateField')), '45');
      await tester.enterText(find.byKey(const Key('paraleloRateField')), '50');
      await tester.tap(find.byKey(const Key('saveRatesButton')));
      await tester.pumpAndSettle();

      expect(
        find.text('Deudas · \$280.00'),
        findsOneWidget,
        reason:
            'Pedro \$200,00 + Ana revalorizada a \$80,00 con la tasa nueva, '
            'en Patrimonio, sin recargar nada a mano',
      );

      await tester.tap(find.byKey(const Key('patrimonioOverflowMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('debtsMenuItem')));
      await tester.pumpAndSettle();

      expect(find.text('Ana te debe \$80.00'), findsOneWidget);
      expect(find.textContaining('tasa 50.00, hoy'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('debtsGlobalAmount'))).data,
        '\$280.00',
      );

      // ---------------------------------------------------------------
      // 4. Crear Claudia (USD, sin apertura) y conciliarla dos veces:
      //    \$37,00 y luego -\$12,00 (cruce de cero, ADR-0017), a través
      //    del mismo ReconcileUseCase real que usa el botón "Conciliar"
      //    de Deudas.
      // ---------------------------------------------------------------
      final claudiaId = await createAccount(
        name: 'Claudia',
        nativeCurrency: CurrencyCode('USD'),
        counterpartyName: 'Claudia',
        eventId: EventId('evt-crear-claudia'),
        deviceId: deviceId,
      );

      final reconcile = await container.read(reconcileUseCaseProvider.future);
      await reconcile(
        eventId: EventId('evt-conciliar-claudia-1'),
        deviceId: deviceId,
        accountId: claudiaId,
        realNativeBalance: Money(
          amount: BigInt.from(3700),
          currency: CurrencyCode('USD'),
        ),
        forceAbsorb: true,
      );
      await reconcile(
        eventId: EventId('evt-conciliar-claudia-2'),
        deviceId: deviceId,
        accountId: claudiaId,
        realNativeBalance: Money(
          amount: BigInt.from(-1200),
          currency: CurrencyCode('USD'),
        ),
        forceAbsorb: true,
      );

      await tester.pumpAndSettle();

      expect(
        find.text('le debés \$12.00 a Claudia'),
        findsOneWidget,
        reason: 'La conciliación con cruce de cero se ve sin recargar nada',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('debtsGlobalAmount'))).data,
        '\$268.00',
        reason: '\$200,00 (Pedro) + \$80,00 (Ana) - \$12,00 (Claudia)',
      );

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(
        find.text('Deudas · \$268.00'),
        findsOneWidget,
        reason:
            'La línea de Patrimonio también refleja la conciliación de '
            'Claudia sin recargar nada',
      );
    },
  );
}
