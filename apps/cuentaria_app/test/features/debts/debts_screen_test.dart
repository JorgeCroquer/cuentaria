import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:cuentaria_app/features/debts/application/debts_providers.dart';
import 'package:cuentaria_app/features/debts/ui/screens/debts_screen.dart';
import 'package:cuentaria_app/features/patrimonio/ui/screens/patrimonio_screen.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:cuentaria_app/providers/tasas_providers.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/domain/rate_observation.dart';

Future<void> pumpWithContainer(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: DebtsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _typeDigits(WidgetTester tester, String digits) async {
  for (final digit in digits.split('')) {
    await tester.tap(find.byKey(Key('keypadDigit_$digit')));
    await tester.pump();
  }
  await tester.tap(find.byKey(const Key('keypadDone')));
  await tester.pump();
}

/// Conciliar/Condonar/Archivar (#244) now live behind the person's ⋮ menu
/// rather than as standalone icons — open it before tapping one of its
/// items.
Future<void> _openDebtActionsMenu(
  WidgetTester tester,
  String personName,
) async {
  await tester.tap(find.byKey(Key('debtActionsMenu_$personName')));
  await tester.pumpAndSettle();
}

/// Confirms whatever outcome the typed amount produced: "Confirmar" when
/// it's Absorb/NothingToReconcile, or the "Absorber de todos modos" escape
/// hatch when it's routed — a Debt Account's swings routinely clear the
/// $1.00 Tolerance (ADR-0019 §3), so Splitwise-style declarations almost
/// always take the routed path (#209, ADR-0022 §4).
Future<void> _confirmReconciliation(WidgetTester tester) async {
  final absorbAnyway = find.byKey(
    const Key('reconciliationAbsorbAnywayButton'),
  );
  if (absorbAnyway.evaluate().isNotEmpty) {
    await tester.ensureVisible(absorbAnyway);
    await tester.tap(absorbAnyway);
  } else {
    await tester.tap(find.byKey(const Key('reconciliationConfirmButton')));
  }
  await tester.pumpAndSettle();
}

void main() {
  Future<ProviderContainer> pumpDebtsScreen(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [isWebProvider.overrideWithValue(true)],
    );
    addTearDown(container.dispose);
    await pumpWithContainer(tester, container);
    return container;
  }

  testWidgets('shows the empty state with a CTA when there are no people', (
    tester,
  ) async {
    await pumpDebtsScreen(tester);

    expect(find.byKey(const Key('debtsEmptyState')), findsOneWidget);
    expect(find.byKey(const Key('createPersonCta')), findsOneWidget);
  });

  testWidgets('creates Pedro in USD and lists him', (tester) async {
    final container = await pumpDebtsScreen(tester);

    await tester.tap(find.byKey(const Key('createPersonCta')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('personNameField')), 'Pedro');
    await tester.tap(find.byKey(const Key('savePersonButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('debtPerson_Pedro')), findsOneWidget);
    expect(find.byKey(const Key('debtsEmptyState')), findsNothing);

    final catalog = await container.read(catalogRepositoryProvider.future);
    final account = catalog.accounts.singleWhere((a) => a.name == 'Pedro');
    expect(account.counterpartyName, 'Pedro');
    expect(account.nativeCurrency, CurrencyCode('USD'));
  });

  testWidgets('creates Ana in VES and lists her below Pedro', (tester) async {
    final container = await pumpDebtsScreen(tester);

    await tester.tap(find.byKey(const Key('createPersonCta')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('personNameField')), 'Pedro');
    await tester.tap(find.byKey(const Key('savePersonButton')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('addPersonFab')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('personNameField')), 'Ana');
    await tester.tap(find.byKey(const Key('personCurrencyDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('VES').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('savePersonButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('debtPerson_Pedro')), findsOneWidget);
    expect(find.byKey(const Key('debtPerson_Ana')), findsOneWidget);

    final catalog = await container.read(catalogRepositoryProvider.future);
    final ana = catalog.accounts.singleWhere((a) => a.name == 'Ana');
    expect(ana.nativeCurrency, CurrencyCode('VES'));
  });

  testWidgets('a debt account starts with a zero opening balance — no '
      'ledger transaction is posted', (tester) async {
    final container = await pumpDebtsScreen(tester);

    await tester.tap(find.byKey(const Key('createPersonCta')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('personNameField')), 'Pedro');
    await tester.tap(find.byKey(const Key('savePersonButton')));
    await tester.pumpAndSettle();

    final store = await container.read(eventStoreProvider.future);
    expect(await store.queryLog(), isEmpty);
  });

  testWidgets('rejects an empty name without creating a person', (
    tester,
  ) async {
    await pumpDebtsScreen(tester);

    await tester.tap(find.byKey(const Key('createPersonCta')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('savePersonButton')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Name is required'), findsOneWidget);
    expect(find.byKey(const Key('debtsEmptyState')), findsOneWidget);
  });

  testWidgets('does not list regular (non-debt) accounts', (tester) async {
    final container = ProviderContainer(
      overrides: [isWebProvider.overrideWithValue(true)],
    );
    addTearDown(container.dispose);
    final catalog = await container.read(catalogRepositoryProvider.future);
    await catalog.saveAccount(
      Account(
        id: AccountId('acc-1'),
        name: 'Binance',
        nativeCurrency: CurrencyCode('USD'),
        isArchived: false,
        updatedAt: DateTime.now(),
      ),
    );

    await pumpWithContainer(tester, container);

    expect(find.text('Binance'), findsNothing);
    expect(find.byKey(const Key('debtsEmptyState')), findsOneWidget);
  });

  testWidgets('Pedro (USD, \$200) reads "Pedro te debe \$200.00" and sets '
      'the global net to \$200.00', (tester) async {
    final container = ProviderContainer(
      overrides: [isWebProvider.overrideWithValue(true)],
    );
    addTearDown(container.dispose);

    final catalog = await container.read(catalogRepositoryProvider.future);
    final deviceId = await container.read(deviceIdProvider.future);
    final projections = container.read(ledgerProjectionsProvider);
    final pedroId = AccountId('pedro');
    await catalog.saveAccount(
      Account(
        id: pedroId,
        name: 'Pedro',
        nativeCurrency: CurrencyCode('USD'),
        isArchived: false,
        updatedAt: DateTime.now(),
        meta: {'counterpartyName': 'Pedro'},
      ),
    );
    final stageEnvelope = catalog.getSystemEnvelope(EnvelopeRole.stage);
    projections.apply(
      Transaction.create(
        postings: [
          Posting(
            target: AccountTarget(pedroId),
            amountNative: Money(
              amount: BigInt.from(20000),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: 20000,
          ),
          Posting(
            target: EnvelopeTarget(stageEnvelope),
            amountNative: Money(
              amount: BigInt.from(20000),
              currency: CurrencyCode('USD'),
            ),
            currency: CurrencyCode('USD'),
            amountUsd: 20000,
          ),
        ],
        metadata: TransactionMetadata(
          eventId: EventId('evt-pedro'),
          type: 'Adjustment',
          occurredAt: DomainTimestamp(DateTime.now().toUtc()),
          recordedAt: DomainTimestamp(DateTime.now().toUtc()),
          deviceId: deviceId,
          schemaVersion: 1,
        ),
      ),
    );

    await pumpWithContainer(tester, container);

    expect(find.text('Pedro te debe \$200.00'), findsOneWidget);
    expect(find.text('\$200.00'), findsWidgets);
  });

  testWidgets(
    'Ana (VES, 4.000 Bs, frozen \$100) with parallel rate 50 registered '
    'shows \$80.00 announcing the rate and its date; without a rate shows '
    '\$100.00 and "sin tasa"',
    (tester) async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      final catalog = await container.read(catalogRepositoryProvider.future);
      final deviceId = await container.read(deviceIdProvider.future);
      final projections = container.read(ledgerProjectionsProvider);
      final anaId = AccountId('ana');
      await catalog.saveAccount(
        Account(
          id: anaId,
          name: 'Ana',
          nativeCurrency: CurrencyCode('VES'),
          isArchived: false,
          updatedAt: DateTime.now(),
          meta: {'counterpartyName': 'Ana'},
        ),
      );
      final stageEnvelope = catalog.getSystemEnvelope(EnvelopeRole.stage);
      projections.apply(
        Transaction.create(
          postings: [
            Posting(
              target: AccountTarget(anaId),
              amountNative: Money(
                amount: BigInt.from(400000),
                currency: CurrencyCode('VES'),
              ),
              currency: CurrencyCode('VES'),
              amountUsd: 10000,
            ),
            Posting(
              target: EnvelopeTarget(stageEnvelope),
              amountNative: Money(
                amount: BigInt.from(400000),
                currency: CurrencyCode('VES'),
              ),
              currency: CurrencyCode('VES'),
              amountUsd: 10000,
            ),
          ],
          metadata: TransactionMetadata(
            eventId: EventId('evt-ana'),
            type: 'Adjustment',
            occurredAt: DomainTimestamp(DateTime.now().toUtc()),
            recordedAt: DomainTimestamp(DateTime.now().toUtc()),
            deviceId: deviceId,
            schemaVersion: 1,
          ),
        ),
      );

      await pumpWithContainer(tester, container);

      expect(find.text('Ana te debe \$100.00'), findsOneWidget);
      expect(find.textContaining('sin tasa'), findsOneWidget);

      final rateSeries = await container.read(rateSeriesProvider.future);
      await rateSeries.append(
        RateObservation(
          currency: CurrencyCode('VES'),
          nativePerUsd: Decimal.parse('50'),
          observedAt: DateTime.now().toUtc(),
          source: 'manual:paralelo',
        ),
      );
      container.invalidate(debtsSnapshotProvider);
      await pumpWithContainer(tester, container);

      expect(find.text('Ana te debe \$80.00'), findsOneWidget);
      expect(find.textContaining('tasa 50.00, hoy'), findsOneWidget);
    },
  );

  testWidgets(
    'Prestar sits at the same horizontal offset for a one-line balance '
    '(Pedro, USD) and a longer rate-announcing one (Ana, VES) — actions '
    'live below the text instead of a vertically-centered trailing column '
    'that danced with content height (#244)',
    (tester) async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      final catalog = await container.read(catalogRepositoryProvider.future);
      final deviceId = await container.read(deviceIdProvider.future);
      final projections = container.read(ledgerProjectionsProvider);
      final stageEnvelope = catalog.getSystemEnvelope(EnvelopeRole.stage);

      Future<void> seed(
        AccountId id,
        String name,
        CurrencyCode currency,
        BigInt nativeAmount,
        int usdCents,
      ) async {
        await catalog.saveAccount(
          Account(
            id: id,
            name: name,
            nativeCurrency: currency,
            isArchived: false,
            updatedAt: DateTime.now(),
            meta: {'counterpartyName': name},
          ),
        );
        projections.apply(
          Transaction.create(
            postings: [
              Posting(
                target: AccountTarget(id),
                amountNative: Money(amount: nativeAmount, currency: currency),
                currency: currency,
                amountUsd: usdCents,
              ),
              Posting(
                target: EnvelopeTarget(stageEnvelope),
                amountNative: Money(amount: nativeAmount, currency: currency),
                currency: currency,
                amountUsd: usdCents,
              ),
            ],
            metadata: TransactionMetadata(
              eventId: EventId('evt-${id.value}'),
              type: 'Adjustment',
              occurredAt: DomainTimestamp(DateTime.now().toUtc()),
              recordedAt: DomainTimestamp(DateTime.now().toUtc()),
              deviceId: deviceId,
              schemaVersion: 1,
            ),
          ),
        );
      }

      await seed(
        AccountId('pedro'),
        'Pedro',
        CurrencyCode('USD'),
        BigInt.from(20000),
        20000,
      );
      await seed(
        AccountId('ana'),
        'Ana',
        CurrencyCode('VES'),
        BigInt.from(400000),
        10000,
      );

      final rateSeries = await container.read(rateSeriesProvider.future);
      await rateSeries.append(
        RateObservation(
          currency: CurrencyCode('VES'),
          nativePerUsd: Decimal.parse('50'),
          observedAt: DateTime.now().toUtc(),
          source: 'manual:paralelo',
        ),
      );

      await pumpWithContainer(tester, container);

      final pedroLegBottom =
          tester.getBottomLeft(find.text('USD: \$200.00')).dy;
      final pedroPrestarTop =
          tester
              .getTopLeft(find.byKey(const Key('debtAction_prestar_Pedro')))
              .dy;
      expect(pedroPrestarTop, greaterThanOrEqualTo(pedroLegBottom));

      final anaLegBottom =
          tester.getBottomLeft(find.textContaining('VES: \$80.00')).dy;
      final anaPrestarTop =
          tester.getTopLeft(find.byKey(const Key('debtAction_prestar_Ana'))).dy;
      expect(anaPrestarTop, greaterThanOrEqualTo(anaLegBottom));

      final pedroPrestarLeft =
          tester
              .getTopLeft(find.byKey(const Key('debtAction_prestar_Pedro')))
              .dx;
      final anaPrestarLeft =
          tester.getTopLeft(find.byKey(const Key('debtAction_prestar_Ana'))).dx;
      expect(pedroPrestarLeft, anaPrestarLeft);
    },
  );

  testWidgets(
    'Conciliar opens the C3 Reconciliation sheet preselecting the Debt '
    'Account, and Archivar is hidden while the balance is not zero (#209)',
    (tester) async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      final catalog = await container.read(catalogRepositoryProvider.future);
      final deviceId = await container.read(deviceIdProvider.future);
      final projections = container.read(ledgerProjectionsProvider);
      final pedroId = AccountId('pedro');
      await catalog.saveAccount(
        Account(
          id: pedroId,
          name: 'Pedro',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.now(),
          meta: {'counterpartyName': 'Pedro'},
        ),
      );
      final stageEnvelope = catalog.getSystemEnvelope(EnvelopeRole.stage);
      projections.apply(
        Transaction.create(
          postings: [
            Posting(
              target: AccountTarget(pedroId),
              amountNative: Money(
                amount: BigInt.from(20000),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: 20000,
            ),
            Posting(
              target: EnvelopeTarget(stageEnvelope),
              amountNative: Money(
                amount: BigInt.from(20000),
                currency: CurrencyCode('USD'),
              ),
              currency: CurrencyCode('USD'),
              amountUsd: 20000,
            ),
          ],
          metadata: TransactionMetadata(
            eventId: EventId('evt-pedro-2'),
            type: 'Adjustment',
            occurredAt: DomainTimestamp(DateTime.now().toUtc()),
            recordedAt: DomainTimestamp(DateTime.now().toUtc()),
            deviceId: deviceId,
            schemaVersion: 1,
          ),
        ),
      );

      await pumpWithContainer(tester, container);

      await tester.tap(find.byKey(const Key('debtActionsMenu_Pedro')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('reconcileDebtAccount_pedro')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('archiveDebtAccount_pedro')), findsNothing);

      await tester.tap(find.byKey(const Key('reconcileDebtAccount_pedro')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('projectedBalanceText')), findsOneWidget);
      expect(find.text('Proyectado: 200.00 USD'), findsOneWidget);

      await tester.tap(find.byKey(const Key('reconciliationCancelButton')));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Archivar appears once the Debt Account is at \$0,00, asks before '
    'archiving, and removes the person from Deudas on confirm (#209)',
    (tester) async {
      final container = await pumpDebtsScreen(tester);

      await tester.tap(find.byKey(const Key('createPersonCta')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('personNameField')),
        'Claudia',
      );
      await tester.tap(find.byKey(const Key('savePersonButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('debtPerson_Claudia')), findsOneWidget);

      final catalog = await container.read(catalogRepositoryProvider.future);
      final claudia = catalog.accounts.singleWhere((a) => a.name == 'Claudia');
      final archiveKey = Key('archiveDebtAccount_${claudia.id.value}');

      await _openDebtActionsMenu(tester, 'Claudia');
      expect(find.byKey(archiveKey), findsOneWidget);

      await tester.tap(find.byKey(archiveKey));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('archiveDebtConfirmButton')), findsOneWidget);

      await tester.tap(find.byKey(const Key('archiveDebtCancelButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('debtPerson_Claudia')), findsOneWidget);

      await _openDebtActionsMenu(tester, 'Claudia');
      await tester.tap(find.byKey(archiveKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('archiveDebtConfirmButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('debtPerson_Claudia')), findsNothing);
      expect(find.byKey(const Key('debtsEmptyState')), findsOneWidget);

      final archived = catalog.accounts.singleWhere((a) => a.name == 'Claudia');
      expect(archived.isArchived, isTrue);
    },
  );

  testWidgets('Claudia (USD, \$0): declaring "me debe \$37,00", then "le debo '
      '\$12,00" (crossing zero), then \$0,00 updates Deudas at each step and '
      'offers to archive; accepting removes her from Deudas and drops the '
      'Patrimonio Deudas line (#209, ADR-0022 §4)', (tester) async {
    final container = await pumpDebtsScreen(tester);

    await tester.tap(find.byKey(const Key('createPersonCta')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('personNameField')), 'Claudia');
    await tester.tap(find.byKey(const Key('savePersonButton')));
    await tester.pumpAndSettle();

    final catalog = await container.read(catalogRepositoryProvider.future);
    final claudia = catalog.accounts.singleWhere((a) => a.name == 'Claudia');
    final reconcileKey = Key('reconcileDebtAccount_${claudia.id.value}');

    // "Me debe $37,00" — the direction selector already defaults there
    // since the balance starts at $0.
    await _openDebtActionsMenu(tester, 'Claudia');
    await tester.tap(find.byKey(reconcileKey));
    await tester.pumpAndSettle();
    await _typeDigits(tester, '3700');
    await tester.pump();
    await _confirmReconciliation(tester);

    expect(find.text('Claudia te debe \$37.00'), findsOneWidget);
    expect(catalog.accounts.where((a) => a.name == 'Claudia').length, 1);

    // "Le debo $12,00" — crosses zero on the very same account.
    await _openDebtActionsMenu(tester, 'Claudia');
    await tester.tap(find.byKey(reconcileKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Le debo'));
    await tester.pump();
    await _typeDigits(tester, '1200');
    await tester.pump();
    await _confirmReconciliation(tester);

    expect(find.text('le debés \$12.00 a Claudia'), findsOneWidget);
    expect(catalog.accounts.where((a) => a.name == 'Claudia').length, 1);

    // $0,00 — saldo cero is declarable and the app offers to archive.
    await _openDebtActionsMenu(tester, 'Claudia');
    await tester.tap(find.byKey(reconcileKey));
    await tester.pumpAndSettle();
    await _typeDigits(tester, '0');
    await tester.pump();
    await _confirmReconciliation(tester);

    final archiveKey = Key('archiveDebtAccount_${claudia.id.value}');
    await _openDebtActionsMenu(tester, 'Claudia');
    expect(find.byKey(archiveKey), findsOneWidget);

    await tester.tap(find.byKey(archiveKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('archiveDebtConfirmButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('debtPerson_Claudia')), findsNothing);
    expect(find.byKey(const Key('debtsEmptyState')), findsOneWidget);

    final archived = catalog.accounts.singleWhere((a) => a.name == 'Claudia');
    expect(archived.isArchived, isTrue);

    // Patrimonio's "Deudas" line drops with her.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PatrimonioScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('debtsLine')), findsNothing);
  });

  testWidgets('Pedro (USD, \$50, "me debe"): leaving the real balance field '
      'empty declares \$0,00 same as typing it, crossing zero and offering '
      'to archive (fix directive gap 1b)', (tester) async {
    final container = await pumpDebtsScreen(tester);

    await tester.tap(find.byKey(const Key('createPersonCta')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('personNameField')), 'Pedro');
    await tester.tap(find.byKey(const Key('savePersonButton')));
    await tester.pumpAndSettle();

    final catalog = await container.read(catalogRepositoryProvider.future);
    final pedro = catalog.accounts.singleWhere((a) => a.name == 'Pedro');
    final reconcileKey = Key('reconcileDebtAccount_${pedro.id.value}');

    // "Me debe $50,00" — the direction selector already defaults there
    // since the balance starts at $0.
    await _openDebtActionsMenu(tester, 'Pedro');
    await tester.tap(find.byKey(reconcileKey));
    await tester.pumpAndSettle();
    await _typeDigits(tester, '5000');
    await tester.pump();
    await _confirmReconciliation(tester);

    expect(find.text('Pedro te debe \$50.00'), findsOneWidget);

    // Back to $0,00 by leaving the field untouched and pressing Listo —
    // an untyped field must declare 0, same as typing "0" (gap 1b).
    await _openDebtActionsMenu(tester, 'Pedro');
    await tester.tap(find.byKey(reconcileKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('keypadDone')));
    await tester.pump();
    await _confirmReconciliation(tester);

    final archiveKey = Key('archiveDebtAccount_${pedro.id.value}');
    await _openDebtActionsMenu(tester, 'Pedro');
    expect(find.byKey(archiveKey), findsOneWidget);
  });

  testWidgets('Condonar from the real DebtsScreen opens the capture sheet with '
      'the "Condonar deuda de Pedro" contextTitle and Pedro\'s account chip '
      'visible and selected (regression of PR #247)', (tester) async {
    final container = ProviderContainer(
      overrides: [isWebProvider.overrideWithValue(true)],
    );
    addTearDown(container.dispose);

    final catalog = await container.read(catalogRepositoryProvider.future);
    await catalog.saveAccount(
      Account(
        id: AccountId('pedro'),
        name: 'Pedro',
        nativeCurrency: CurrencyCode('USD'),
        isArchived: false,
        updatedAt: DateTime.now(),
        meta: {'counterpartyName': 'Pedro'},
      ),
    );

    await pumpWithContainer(tester, container);

    await _openDebtActionsMenu(tester, 'Pedro');
    await tester.tap(find.byKey(const Key('debtAction_condonar_Pedro')));
    await tester.pumpAndSettle();

    expect(find.text('Condonar deuda de Pedro'), findsOneWidget);
    final pedroChip = tester.widget<ChoiceChip>(
      find.byKey(const Key('accountChip_pedro')),
    );
    expect(pedroChip.selected, isTrue);
  });
}
