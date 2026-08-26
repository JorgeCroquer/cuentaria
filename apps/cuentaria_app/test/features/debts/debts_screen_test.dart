import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:cuentaria_app/features/debts/application/debts_providers.dart';
import 'package:cuentaria_app/features/debts/ui/screens/debts_screen.dart';
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

      expect(find.byKey(archiveKey), findsOneWidget);

      await tester.tap(find.byKey(archiveKey));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('archiveDebtConfirmButton')), findsOneWidget);

      await tester.tap(find.byKey(const Key('archiveDebtCancelButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('debtPerson_Claudia')), findsOneWidget);

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
}
