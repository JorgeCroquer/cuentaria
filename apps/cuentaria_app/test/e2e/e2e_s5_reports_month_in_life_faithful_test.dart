/// S5 faithful end-to-end test (issue #266, ADR-0024): a "month in the
/// life" of Reportes — a fixed, realistic three-month scenario (a two-months
/// -ago "julio", a one-month-ago "agosto" and the current "septiembre",
/// always relative to wall-clock `DateTime.now()` so the test never rots)
/// replayed through the real domain factories and asserted against the
/// real Reportes screen — no mocks.
///
/// Julio: apertura de Banco $1.000,00, ingreso «Acme» $400,00, gasto Comida
/// $100,00. Agosto: gasto Comida $40,00 (revertido en septiembre), gasto
/// Comida 4.000,00 Bs congelado a $100,00 (tasa 40,00), Transfer $500,00
/// Banco -> Efectivo, ingreso «Acme» $500,00, ingreso sin fuente $150,00,
/// una CryptoSale parcial (mitad de la posición) que realiza +$12,00 y deja
/// un residual de $88,00 en Cripto, una nueva tasa paralela de BTC que
/// diverge de la de apertura (para que el residual tenga un valor de
/// mercado distinto de su costo real), una conciliación que absorbe
/// -$0,60, y un gasto de $20,00 en Transporte el último día del mes a las
/// 23:30. Septiembre: Reversal del gasto de $40,00 de agosto.
///
/// Drives the real app shell ([MyApp]) with in-memory adapters
/// ([isWebProvider]) and posts every movement through the very same
/// application-layer factories the UI itself calls ([createAccountProvider],
/// [quickAddExpenseUseCaseProvider], [quickAddIncomeUseCaseProvider],
/// [quickAddMoverUseCaseProvider], [reconcileUseCaseProvider],
/// [recordReversalProvider], plus [RecordRealization.cryptoSale] directly —
/// there is no quick-add UI for selling a crypto asset yet) — then reads
/// the real [ReportesScreen] and [PatrimonioEnTiempoScreen] widgets, no
/// mocks anywhere in the chain.
library;

import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/ledger/factories/record_realization.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:cuentaria_app/features/accounts/application/account_providers.dart';
import 'package:cuentaria_app/features/capture/application/capture_providers.dart';
import 'package:cuentaria_app/features/cloud_copy/application/cloud_copy_providers.dart';
import 'package:cuentaria_app/features/movements/application/movements_providers.dart';
import 'package:cuentaria_app/features/reconciliation/application/reconciliation_providers.dart';
import 'package:cuentaria_app/features/reportes/application/patrimonio_en_tiempo_providers.dart';
import 'package:cuentaria_app/features/reportes/ui/screens/patrimonio_en_tiempo_screen.dart';
import 'package:cuentaria_app/features/reportes/ui/screens/reportes_screen.dart';
import 'package:cuentaria_app/features/reportes/ui/widgets/month_selector.dart'
    show monthName;
import 'package:cuentaria_app/main.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:cuentaria_app/providers/tasas_providers.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reportes/reportes.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/domain/rate_observation.dart';

const _deviceId = 'device-s5-e2e';

/// Every "julio/agosto/septiembre" date is anchored to real wall-clock
/// `DateTime.now()` (two/one/zero months back) rather than a literal
/// calendar year: [ReportesScreen] and [PatrimonioEnTiempoScreen] both cut
/// "the current month" from the real clock with no override, so pinning the
/// scenario to a fixed past year would eventually push "agosto" outside
/// Patrimonio en el tiempo's rolling 12-point window.
DateTime _monthStart(DateTime now, int monthsAgo) =>
    DateTime(now.year, now.month - monthsAgo, 1);

DateTime _on(DateTime monthStart, int day, [int hour = 0, int minute = 0]) =>
    DateTime(monthStart.year, monthStart.month, day, hour, minute);

/// The last calendar day of [monthStart]'s month — calendar-agnostic
/// (works whether that month has 28, 30 or 31 days), for the "31 de agosto
/// a las 23:30" boundary case (ADR-0024 §4: the cut is local wall-clock, so
/// a late-night expense on the month's last day must not slip into the
/// next month just because it's stored in UTC).
DateTime _lastDayOf(DateTime monthStart, [int hour = 0, int minute = 0]) =>
    DateTime(monthStart.year, monthStart.month + 1, 0, hour, minute);

DomainTimestamp _ts(DateTime local) => DomainTimestamp(local.toUtc());

String _monthLabel(DateTime monthStart) {
  final name = monthName(monthStart.month);
  return '${name[0].toUpperCase()}${name.substring(1)} ${monthStart.year}';
}

void main() {
  testWidgets(
    'a month in the life of Reportes: julio/agosto/septiembre replayed '
    'through real factories — Gasto por sobre, Ingreso por fuente and '
    'Patrimonio en el tiempo all agree, through the real screens (#266)',
    (tester) async {
      final now = DateTime.now();
      final julyMonth = _monthStart(now, 2);
      final augustMonth = _monthStart(now, 1);
      final septemberMonth = _monthStart(now, 0);

      final container = ProviderContainer(
        overrides: [
          isWebProvider.overrideWithValue(true),
          cloudCopyDebounceProvider.overrideWithValue(Duration.zero),
        ],
      );
      addTearDown(container.dispose);

      // -- Real repositories/use-cases, wired exactly like the composition
      // root wires them for the UI ---------------------------------------
      final catalog = await container.read(catalogRepositoryProvider.future);
      final store = await container.read(eventStoreProvider.future);
      final projections = container.read(ledgerProjectionsProvider);
      final eventBus = container.read(eventBusProvider);
      final createAccount = await container.read(createAccountProvider.future);
      final quickAddExpense = await container.read(
        quickAddExpenseUseCaseProvider.future,
      );
      final quickAddIncome = await container.read(
        quickAddIncomeUseCaseProvider.future,
      );
      final quickAddMover = await container.read(
        quickAddMoverUseCaseProvider.future,
      );
      final reconcile = await container.read(reconcileUseCaseProvider.future);
      final recordReversal = await container.read(
        recordReversalProvider.future,
      );
      // No quick-add UI exists yet for selling a crypto asset (#266 is the
      // first scenario that needs one) — composed the same way
      // `quickAddExpenseUseCaseProvider` composes `RecordRealization`.
      final recordRealization = RecordRealization(
        record: RecordTransaction(
          store: store,
          projections: projections,
          eventBus: eventBus,
          validator: ReferentialIntegrityValidator(catalog),
        ),
        catalog: catalog,
        projections: projections,
      );

      final comidaId = EnvelopeId('comida');
      final transporteId = EnvelopeId('transporte');
      await catalog.saveEnvelope(
        Envelope(
          id: comidaId,
          name: 'Comida',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: now,
        ),
      );
      await catalog.saveEnvelope(
        Envelope(
          id: transporteId,
          name: 'Transporte',
          role: EnvelopeRole.none,
          isArchived: false,
          updatedAt: now,
        ),
      );

      // ---------------------------------------------------------------
      // Julio: apertura de Banco $1.000,00, ingreso «Acme» $400,00, gasto
      // Comida $100,00.
      // ---------------------------------------------------------------
      final bancoId = await createAccount(
        name: 'Banco',
        nativeCurrency: CurrencyCode('USD'),
        openingBalance: Money(
          amount: BigInt.from(100000),
          currency: CurrencyCode('USD'),
        ),
        eventId: EventId('evt-open-banco'),
        deviceId: _deviceId,
        occurredAt: _ts(_on(julyMonth, 1)),
      );

      await quickAddIncome(
        eventId: EventId('evt-jul-income-acme'),
        deviceId: _deviceId,
        accountId: bancoId,
        amount: Money(
          amount: BigInt.from(40000),
          currency: CurrencyCode('USD'),
        ),
        source: 'Acme',
        occurredAt: _ts(_on(julyMonth, 10)),
      );

      await quickAddExpense(
        eventId: EventId('evt-jul-food'),
        deviceId: _deviceId,
        accountId: bancoId,
        envelopeId: comidaId,
        amount: Money(
          amount: BigInt.from(10000),
          currency: CurrencyCode('USD'),
        ),
        occurredAt: _ts(_on(julyMonth, 15)),
      );

      // ---------------------------------------------------------------
      // Agosto: Efectivo (destino del Transfer), BdV (Bs, apertura
      // 4.000,00 Bs a tasa 40,00 -> congela $100,00) y Cripto (apertura
      // con costo base $176,00, a una tasa 1,00 — el catálogo exige una
      // tasa para *cualquier* moneda que aparezca en él, incluso con saldo
      // cero, o el punto queda en "sin tasa disponible"; aquí, además, solo
      // se vende la mitad de la posición más abajo, dejando un residual de
      // $88,00 cuyo valor de mercado diverge del costo real una vez que se
      // registra una tasa paralela nueva — ver más abajo).
      // ---------------------------------------------------------------
      final efectivoId = await createAccount(
        name: 'Efectivo',
        nativeCurrency: CurrencyCode('USD'),
        eventId: EventId('evt-open-efectivo'),
        deviceId: _deviceId,
      );

      final bdvId = await createAccount(
        name: 'BdV',
        nativeCurrency: CurrencyCode('VES'),
        openingBalance: Money(
          amount: BigInt.from(400000),
          currency: CurrencyCode('VES'),
        ),
        openingBalanceRate: Decimal.parse('40.00'),
        eventId: EventId('evt-open-bdv'),
        deviceId: _deviceId,
        occurredAt: _ts(_on(augustMonth, 1)),
      );

      final criptoId = await createAccount(
        name: 'Cripto',
        nativeCurrency: CurrencyCode('BTC'),
        openingBalance: Money(
          amount: BigInt.from(17600),
          currency: CurrencyCode('BTC'),
        ),
        openingBalanceRate: Decimal.parse('1.00'),
        eventId: EventId('evt-open-cripto'),
        deviceId: _deviceId,
        occurredAt: _ts(_on(augustMonth, 1)),
      );

      // Gasto Comida $40,00 (revertido en septiembre).
      await quickAddExpense(
        eventId: EventId('evt-aug-food-usd-40'),
        deviceId: _deviceId,
        accountId: bancoId,
        envelopeId: comidaId,
        amount: Money(amount: BigInt.from(4000), currency: CurrencyCode('USD')),
        occurredAt: _ts(_on(augustMonth, 5)),
      );

      // Ingreso «Acme» $500,00.
      await quickAddIncome(
        eventId: EventId('evt-aug-income-acme'),
        deviceId: _deviceId,
        accountId: bancoId,
        amount: Money(
          amount: BigInt.from(50000),
          currency: CurrencyCode('USD'),
        ),
        source: 'Acme',
        occurredAt: _ts(_on(augustMonth, 8)),
      );

      // Gasto Comida 4.000,00 Bs, congelado a $100,00 a la tasa 40,00
      // recién anunciada por la apertura de BdV (delta cero: se dispone el
      // saldo completo a la misma tasa a la que se abrió).
      await quickAddExpense(
        eventId: EventId('evt-aug-food-bs'),
        deviceId: _deviceId,
        accountId: bdvId,
        envelopeId: comidaId,
        amount: Money(
          amount: BigInt.from(400000),
          currency: CurrencyCode('VES'),
        ),
        occurredAt: _ts(_on(augustMonth, 10)),
      );

      // Transfer $500,00 Banco -> Efectivo.
      await quickAddMover(
        eventId: EventId('evt-aug-transfer'),
        deviceId: _deviceId,
        sourceAccountId: bancoId,
        destinationAccountId: efectivoId,
        givenAmount: Money(
          amount: BigInt.from(50000),
          currency: CurrencyCode('USD'),
        ),
        occurredAt: _ts(_on(augustMonth, 12)),
      );

      // Ingreso sin fuente $150,00.
      await quickAddIncome(
        eventId: EventId('evt-aug-income-sin-fuente'),
        deviceId: _deviceId,
        accountId: bancoId,
        amount: Money(
          amount: BigInt.from(15000),
          currency: CurrencyCode('USD'),
        ),
        source: '',
        occurredAt: _ts(_on(augustMonth, 18)),
      );

      // CryptoSale: se vende la mitad de la posición de Cripto (costo base
      // proporcional $88,00 de los $176,00 totales) por $100,00, realizando
      // +$12,00 hacia Diferencial y dejando un residual de $88,00 (mitad
      // del saldo original) en la cuenta.
      await recordRealization.cryptoSale(
        eventId: EventId('evt-aug-crypto-sale'),
        deviceId: _deviceId,
        cryptoAccountId: criptoId,
        destinationUsdAccountId: bancoId,
        quantity: Money(
          amount: BigInt.from(8800),
          currency: CurrencyCode('BTC'),
        ),
        usdAmountReceived: Money(
          amount: BigInt.from(10000),
          currency: CurrencyCode('USD'),
        ),
        rateRef: '1.00 BTC/USD',
        occurredAt: _ts(_on(augustMonth, 20)),
      );

      // Nueva tasa paralela de BTC (1,10, distinta de la 1,00 de apertura),
      // registrada a través del mismo caso de uso real que usa la pantalla
      // Patrimonio para "Actualizar tasas" — sin esto, el residual de
      // Cripto se valoraría con la tasa de apertura y el valor de mercado
      // coincidiría trivialmente con el costo real, sin ejercer la
      // divergencia que el diferencial no realizado de Patrimonio en el
      // tiempo debe reflejar.
      final recordRate = await container.read(recordRateUseCaseProvider.future);
      await recordRate.execute(
        paralelo: RateObservation(
          currency: CurrencyCode('BTC'),
          nativePerUsd: Decimal.parse('1.10'),
          observedAt: _on(augustMonth, 25).toUtc(),
          source: 'manual:paralelo',
        ),
      );

      // Conciliación de Banco: delta -$0,60, dentro de la Tolerancia de
      // $1,00 (ADR-0019), se absorbe en un solo toque contra Ajustes.
      final bancoBalanceBeforeReconcile = projections.accountBalance(bancoId);
      final reconciledBalance = Money(
        amount: bancoBalanceBeforeReconcile.native.amount - BigInt.from(60),
        currency: CurrencyCode('USD'),
      );
      await reconcile(
        eventId: EventId('evt-aug-reconcile'),
        deviceId: _deviceId,
        accountId: bancoId,
        realNativeBalance: reconciledBalance,
        occurredAt: _ts(_on(augustMonth, 21)),
      );

      // Gasto $20,00 en Transporte, el último día de agosto a las 23:30.
      await quickAddExpense(
        eventId: EventId('evt-aug-transport'),
        deviceId: _deviceId,
        accountId: bancoId,
        envelopeId: transporteId,
        amount: Money(amount: BigInt.from(2000), currency: CurrencyCode('USD')),
        occurredAt: _ts(_lastDayOf(augustMonth, 23, 30)),
      );

      // ---------------------------------------------------------------
      // Septiembre: Reversal del gasto de $40,00 de agosto — la historia
      // de agosto no se mueve (ADR-0024 §3), la resta cae en agosto.
      // ---------------------------------------------------------------
      await recordReversal(
        eventId: EventId('evt-sep-reversal-food-40'),
        deviceId: _deviceId,
        originalEventId: EventId('evt-aug-food-usd-40'),
        occurredAt: _ts(_on(septemberMonth, 5)),
      );

      // ---------------------------------------------------------------
      // Ahora sí: la pantalla Reportes real, ya con todo el escenario en
      // el log. Se navega desde Patrimonio, igual que un usuario real.
      // ---------------------------------------------------------------
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const MyApp()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('patrimonioOverflowMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reportsMenuItem')));
      await tester.pumpAndSettle();

      expect(find.byType(ReportesScreen), findsOneWidget);
      // ReportesScreen opens on the real current month with no override,
      // exactly like Patrimonio en el tiempo below — "septiembre" here IS
      // that current month by construction (0 months back).
      expect(find.text(_monthLabel(septemberMonth)), findsOneWidget);

      // -- Julio: el Opening de $1.000,00 no es ingreso — el total es
      // exactamente el ingreso de Acme, $400,00. ------------------------
      await tester.tap(find.byKey(const Key('reportesPreviousMonthButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reportesPreviousMonthButton')));
      await tester.pumpAndSettle();

      expect(find.text(_monthLabel(julyMonth)), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('incomeBySourceTotal'))).data,
        '\$400.00',
      );

      // -- Agosto: Gasto por sobre — Comida $100,00 (el gasto de $40,00
      // revertido en septiembre no cuenta, los 4.000,00 Bs sí), Transporte
      // $20,00 (el de las 23:30 cae en agosto), total $120,00; Ajustes
      // -$0,60 y Diferencial realizado $12,00 como renglones propios; el
      // Transfer nunca aparece. -------------------------------------------
      await tester.tap(find.byKey(const Key('reportesNextMonthButton')));
      await tester.pumpAndSettle();

      expect(find.text(_monthLabel(augustMonth)), findsOneWidget);

      expect(
        tester
            .widget<Text>(find.byKey(const Key('spendingByEnvelopeTotal')))
            .data,
        '\$120.00',
      );

      final comidaRow = find.byKey(Key('spendingRow_${comidaId.value}'));
      expect(
        find.descendant(of: comidaRow, matching: find.text('Comida')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: comidaRow,
          matching: find.text(
            '\$100.00 · +0% vs ${monthName(julyMonth.month)}',
          ),
        ),
        findsOneWidget,
      );

      final transporteRow = find.byKey(
        Key('spendingRow_${transporteId.value}'),
      );
      expect(
        find.descendant(of: transporteRow, matching: find.text('Transporte')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: transporteRow, matching: find.text('\$20.00')),
        findsOneWidget,
      );

      final adjustmentsEnvelopeId = catalog.getSystemEnvelope(
        EnvelopeRole.adjustments,
      );
      final adjustmentsRow = find.byKey(
        Key('spendingRow_${adjustmentsEnvelopeId.value}'),
      );
      expect(
        find.descendant(of: adjustmentsRow, matching: find.text('Ajustes')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: adjustmentsRow, matching: find.text('\$-0.60')),
        findsOneWidget,
      );

      final differentialEnvelopeId = catalog.getSystemEnvelope(
        EnvelopeRole.differential,
      );
      final differentialRow = find.byKey(
        Key('spendingRow_${differentialEnvelopeId.value}'),
      );
      expect(
        find.descendant(
          of: differentialRow,
          matching: find.text('Diferencial realizado'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: differentialRow, matching: find.text('\$12.00')),
        findsOneWidget,
      );

      // -- Agosto: Ingreso por fuente — Acme $500,00 (+25% vs julio),
      // Sin fuente $150,00 (el diferencial realizado de la CryptoSale no
      // cuenta como ingreso — #266 fix), total $650,00. -------------------
      expect(
        tester.widget<Text>(find.byKey(const Key('incomeBySourceTotal'))).data,
        '\$650.00',
      );

      final acmeRow = find.byKey(const Key('incomeRow_Acme'));
      expect(
        find.descendant(
          of: acmeRow,
          matching: find.text(
            '\$500.00 · +25% vs ${monthName(julyMonth.month)}',
          ),
        ),
        findsOneWidget,
      );

      final sinFuenteRow = find.byKey(const Key('incomeRow_Sin fuente'));
      expect(
        find.descendant(of: sinFuenteRow, matching: find.text('\$150.00')),
        findsOneWidget,
      );

      // -- Septiembre: el Reversal resta en agosto, no aparece como gasto
      // negativo — Comida queda ausente del todo. --------------------------
      await tester.tap(find.byKey(const Key('reportesNextMonthButton')));
      await tester.pumpAndSettle();

      expect(find.text(_monthLabel(septemberMonth)), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('reportSection_gastoPorSobre')),
          matching: find.text('Aún no hay datos para este mes'),
        ),
        findsOneWidget,
      );

      // ---------------------------------------------------------------
      // Patrimonio en el tiempo: el punto de fin de agosto coincide con
      // el saldo real que dejó el escenario — Banco $1.489,40 (apertura
      // $1.000,00 - $40,00 - $500,00 transfer + $500,00 + $150,00 +
      // $100,00 crypto - $0,60 - $20,00) + Efectivo $500,00 + Cripto
      // residual $88,00 (costo real congelado a la tasa 1,00 de apertura),
      // con BdV en cero: costo real $2.077,40.
      //
      // El valor de mercado difiere solo en el residual de Cripto, ahora
      // valorado a la tasa paralela nueva de 1,10 registrada más arriba:
      // $88,00 / 1,10 = $80,00 (Banco/Efectivo/BdV no tienen moneda
      // extranjera con saldo, así que no se mueven). Valor de mercado
      // total: $2.069,40. El diferencial no realizado de agosto es
      // exactamente la diferencia entre esas dos líneas: $2.069,40 -
      // $2.077,40 = -$8,00 — ya no un caso degenerado de diferencial cero.
      // ---------------------------------------------------------------
      await tester.tap(find.byKey(const Key('patrimonioEnTiempoEntry')));
      await tester.pumpAndSettle();

      expect(find.byType(PatrimonioEnTiempoScreen), findsOneWidget);

      final points = await container.read(
        patrimonioEnTiempoPointsProvider.future,
      );
      final augustReportMonth = ReportMonth(
        augustMonth.year,
        augustMonth.month,
      );
      final augustIndex = points.indexWhere(
        (p) => p.month == augustReportMonth,
      );
      expect(
        augustIndex,
        isNonNegative,
        reason: 'agosto debe estar dentro de los últimos 12 puntos',
      );

      final tapsBack = points.length - 1 - augustIndex;
      for (var i = 0; i < tapsBack; i++) {
        await tester.tap(
          find.byKey(const Key('patrimonioEnTiempoPreviousMonthButton')),
        );
        await tester.pumpAndSettle();
      }

      expect(find.text(_monthLabel(augustMonth)), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('patrimonioEnTiempoRealCost')))
            .data,
        'Costo real: \$2077.40',
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('patrimonioEnTiempoMarketValue')),
            )
            .data,
        'Valor de mercado: \$2069.40',
      );
    },
  );
}
