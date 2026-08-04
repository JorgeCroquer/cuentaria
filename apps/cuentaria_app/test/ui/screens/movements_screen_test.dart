import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/catalog/models/envelope_appearance.dart';
import 'package:contabilidad/application/ledger/factories/record_acquisition_conversion.dart';
import 'package:contabilidad/application/ledger/factories/record_income.dart';
import 'package:contabilidad/application/ledger/factories/record_transfer.dart';
import 'package:contabilidad/application/ledger/factories/record_usd_expense.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:cuentaria_app/ui/screens/movements/movement_detail_screen.dart';
import 'package:cuentaria_app/ui/screens/movements/movements_screen.dart';
import 'package:cuentaria_app/ui/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_kernel/shared_kernel.dart';

Future<void> _pumpWithRouter(
  WidgetTester tester,
  ProviderContainer container,
) async {
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
}

Future<void> _recordExpense(
  ProviderContainer container, {
  required String eventId,
  required String memo,
}) async {
  final catalog = await container.read(catalogRepositoryProvider.future);
  final store = await container.read(eventStoreProvider.future);
  final projections = container.read(ledgerProjectionsProvider);
  final eventBus = container.read(eventBusProvider);
  final deviceId = await container.read(deviceIdProvider.future);

  final recordTransaction = RecordTransaction(
    store: store,
    projections: projections,
    eventBus: eventBus,
    validator: ReferentialIntegrityValidator(catalog),
  );
  final recordExpense = RecordUsdExpense(
    record: recordTransaction,
    catalog: catalog,
  );

  await recordExpense(
    eventId: EventId(eventId),
    deviceId: deviceId,
    accountId: AccountId('acc-usd'),
    envelopeId: EnvelopeId('env-food'),
    amount: Money(amount: BigInt.from(1200), currency: CurrencyCode('USD')),
    memo: memo,
  );
}

Future<void> _recordIncome(
  ProviderContainer container, {
  required String eventId,
  required int amountCents,
}) async {
  final catalog = await container.read(catalogRepositoryProvider.future);
  final store = await container.read(eventStoreProvider.future);
  final projections = container.read(ledgerProjectionsProvider);
  final eventBus = container.read(eventBusProvider);
  final deviceId = await container.read(deviceIdProvider.future);

  final recordTransaction = RecordTransaction(
    store: store,
    projections: projections,
    eventBus: eventBus,
    validator: ReferentialIntegrityValidator(catalog),
  );
  final recordIncome = RecordIncome(
    record: recordTransaction,
    catalog: catalog,
  );

  await recordIncome(
    eventId: EventId(eventId),
    deviceId: deviceId,
    accountId: AccountId('acc-usd'),
    amount: Money(
      amount: BigInt.from(amountCents),
      currency: CurrencyCode('USD'),
    ),
    source: 'Cliente X',
  );
}

Future<void> _recordTransfer(
  ProviderContainer container, {
  required String eventId,
}) async {
  final catalog = await container.read(catalogRepositoryProvider.future);
  final store = await container.read(eventStoreProvider.future);
  final projections = container.read(ledgerProjectionsProvider);
  final eventBus = container.read(eventBusProvider);
  final deviceId = await container.read(deviceIdProvider.future);

  final recordTransaction = RecordTransaction(
    store: store,
    projections: projections,
    eventBus: eventBus,
    validator: ReferentialIntegrityValidator(catalog),
  );
  final recordTransfer = RecordTransfer(
    record: recordTransaction,
    catalog: catalog,
    projections: projections,
  );

  await recordTransfer(
    eventId: EventId(eventId),
    deviceId: deviceId,
    sourceAccountId: AccountId('acc-usd'),
    destinationAccountId: AccountId('acc-usd-2'),
    amount: Money(amount: BigInt.from(10000), currency: CurrencyCode('USD')),
  );
}

Future<void> _recordAcquisitionConversion(
  ProviderContainer container, {
  required String eventId,
}) async {
  final catalog = await container.read(catalogRepositoryProvider.future);
  final store = await container.read(eventStoreProvider.future);
  final projections = container.read(ledgerProjectionsProvider);
  final eventBus = container.read(eventBusProvider);
  final deviceId = await container.read(deviceIdProvider.future);

  final recordTransaction = RecordTransaction(
    store: store,
    projections: projections,
    eventBus: eventBus,
    validator: ReferentialIntegrityValidator(catalog),
  );
  final recordAcquisitionConversion = RecordAcquisitionConversion(
    record: recordTransaction,
    catalog: catalog,
  );

  await recordAcquisitionConversion(
    eventId: EventId(eventId),
    deviceId: deviceId,
    sourceUsdAccountId: AccountId('acc-usd'),
    destinationForeignAccountId: AccountId('acc-ves'),
    usdAmount: Money(amount: BigInt.from(15000), currency: CurrencyCode('USD')),
    foreignAmountReceived: Money(
      amount: BigInt.from(750000),
      currency: CurrencyCode('VES'),
    ),
    rateRef: '50.00 VES/USD',
  );
}

Future<ProviderContainer> _seededContainer() async {
  final container = ProviderContainer(
    overrides: [isWebProvider.overrideWithValue(true)],
  );
  final catalog = await container.read(catalogRepositoryProvider.future);
  await catalog.saveAccount(
    Account(
      id: AccountId('acc-usd'),
      name: 'Wallet',
      nativeCurrency: CurrencyCode('USD'),
      isArchived: false,
      updatedAt: DateTime.now(),
    ),
  );
  await catalog.saveAccount(
    Account(
      id: AccountId('acc-usd-2'),
      name: 'Savings',
      nativeCurrency: CurrencyCode('USD'),
      isArchived: false,
      updatedAt: DateTime.now(),
    ),
  );
  await catalog.saveAccount(
    Account(
      id: AccountId('acc-ves'),
      name: 'Bs Wallet',
      nativeCurrency: CurrencyCode('VES'),
      isArchived: false,
      updatedAt: DateTime.now(),
    ),
  );
  await catalog.saveEnvelope(
    Envelope(
      id: EnvelopeId('env-food'),
      name: 'Food',
      role: EnvelopeRole.none,
      isArchived: false,
      updatedAt: DateTime.now(),
    ).withAppearance(
      const EnvelopeAppearance(iconId: 'restaurant', colorIndex: 3),
    ),
  );
  return container;
}

void main() {
  group('MovementsScreen', () {
    testWidgets('shows guidance instead of an empty list', (tester) async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      await _pumpWithRouter(tester, container);

      expect(find.byKey(const Key('movementsEmptyState')), findsOneWidget);
    });

    testWidgets(
      'lists a recorded transaction with its Envelope icon/color and memo',
      (tester) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        await _recordExpense(container, eventId: 'evt-1', memo: 'Groceries');

        await _pumpWithRouter(tester, container);

        expect(find.byKey(const Key('movement_evt-1')), findsOneWidget);
        expect(find.text('Gasto'), findsOneWidget);
        expect(find.text('Expense'), findsNothing);
        expect(find.textContaining('Groceries'), findsOneWidget);

        final icon = tester.widget<Icon>(
          find.descendant(
            of: find.byKey(const Key('movement_evt-1')),
            matching: find.byType(Icon),
          ),
        );
        expect(icon.icon, AppIcons.iconFor('restaurant'));
      },
    );

    testWidgets('shows the signed USD amount actually moved per Account (not a '
        'double count across Account+Envelope postings)', (tester) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      await _recordIncome(container, eventId: 'evt-income', amountCents: 50000);
      await _recordExpense(
        container,
        eventId: 'evt-expense',
        memo: 'Groceries',
      );

      await _pumpWithRouter(tester, container);

      expect(
        find.descendant(
          of: find.byKey(const Key('movement_evt-income')),
          matching: find.text('\$500.00'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('movement_evt-expense')),
          matching: find.text('-\$12.00'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'shows the moved amount for a same-currency Transfer between own '
      'accounts, not the \$0.00 net',
      (tester) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        await _recordTransfer(container, eventId: 'evt-transfer');

        await _pumpWithRouter(tester, container);

        expect(
          find.descendant(
            of: find.byKey(const Key('movement_evt-transfer')),
            matching: find.text('\$100.00'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'shows the moved amount for a cross-currency AcquisitionConversion '
      'between own accounts, not the \$0.00 net',
      (tester) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        await _recordAcquisitionConversion(
          container,
          eventId: 'evt-conversion',
        );

        await _pumpWithRouter(tester, container);

        expect(
          find.descendant(
            of: find.byKey(const Key('movement_evt-conversion')),
            matching: find.text('\$150.00'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'tapping a movement opens its detail with postings and a Reversar '
      'action',
      (tester) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        await _recordExpense(container, eventId: 'evt-1', memo: 'Groceries');

        await _pumpWithRouter(tester, container);
        await tester.tap(find.byKey(const Key('movement_evt-1')));
        await tester.pumpAndSettle();

        expect(find.byType(MovementDetailScreen), findsOneWidget);
        expect(find.text('Gasto'), findsOneWidget);
        expect(find.text('Expense'), findsNothing);
        expect(find.textContaining('Wallet'), findsOneWidget);
        expect(find.textContaining('Food'), findsOneWidget);
        expect(find.byKey(const Key('reverseButton')), findsOneWidget);
      },
    );

    testWidgets(
      'reversing a movement appends its negation and refuses a second '
      'reversal (double-reversal guard)',
      (tester) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        await _recordExpense(container, eventId: 'evt-1', memo: 'Groceries');

        await _pumpWithRouter(tester, container);
        await tester.tap(find.byKey(const Key('movement_evt-1')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('reverseButton')));
        await tester.pumpAndSettle();

        expect(find.byType(MovementsScreen), findsOneWidget);

        final store = await container.read(eventStoreProvider.future);
        final log = await store.queryLog();
        expect(log.length, 2);
        expect(log.any((t) => t.metadata.type == 'Reversal'), isTrue);

        await tester.tap(find.byKey(const Key('movement_evt-1')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('alreadyReversedNotice')), findsOneWidget);
        expect(find.byKey(const Key('reverseButton')), findsNothing);
      },
    );
  });
}
