import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:cuentaria_app/features/debts/ui/screens/debts_screen.dart';
import 'package:cuentaria_app/features/patrimonio/application/patrimonio_providers.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';

/// #208: Prestar/Cobrar/Condonar from a person's row in Deudas, driving the
/// existing Mover/Gasto capture flows with the Debt Account preselected —
/// per the PRD's verification script.
Future<ProviderContainer> _pumpDebtsScreen(WidgetTester tester) async {
  final container = ProviderContainer(
    overrides: [isWebProvider.overrideWithValue(true)],
  );
  addTearDown(container.dispose);

  final catalog = await container.read(catalogRepositoryProvider.future);
  await catalog.saveAccount(
    Account(
      id: AccountId('efectivo'),
      name: 'Efectivo',
      nativeCurrency: CurrencyCode('USD'),
      isArchived: false,
      updatedAt: DateTime.now(),
    ),
  );
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
  await catalog.saveEnvelope(
    Envelope(
      id: EnvelopeId('comida'),
      name: 'Comida',
      role: EnvelopeRole.none,
      isArchived: false,
      updatedAt: DateTime.now(),
    ),
  );

  final deviceId = await container.read(deviceIdProvider.future);
  final projections = container.read(ledgerProjectionsProvider);
  final stageEnvelope = catalog.getSystemEnvelope(EnvelopeRole.stage);
  projections.apply(
    Transaction.create(
      postings: [
        Posting(
          target: AccountTarget(AccountId('efectivo')),
          amountNative: Money(
            amount: BigInt.from(100000),
            currency: CurrencyCode('USD'),
          ),
          currency: CurrencyCode('USD'),
          amountUsd: 100000,
        ),
        Posting(
          target: EnvelopeTarget(stageEnvelope),
          amountNative: Money(
            amount: BigInt.from(100000),
            currency: CurrencyCode('USD'),
          ),
          currency: CurrencyCode('USD'),
          amountUsd: 100000,
        ),
      ],
      metadata: TransactionMetadata(
        eventId: EventId('evt-efectivo'),
        type: 'Adjustment',
        occurredAt: DomainTimestamp(DateTime.now().toUtc()),
        recordedAt: DomainTimestamp(DateTime.now().toUtc()),
        deviceId: deviceId,
        schemaVersion: 1,
      ),
    ),
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: DebtsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _enterAmount(WidgetTester tester, String digits) async {
  await tester.ensureVisible(find.byKey(const Key('numericKeypad')));
  for (final digit in digits.split('')) {
    await tester.tap(find.byKey(Key('keypadDigit_$digit')));
  }
  await tester.pump();
}

void main() {
  testWidgets(
    'Prestar \$200 from Efectivo to Pedro (USD, saldo \$0): "Pedro te debe '
    '\$200.00", Efectivo baja \$200.00, ningún Sobre cambia, patrimonio neto '
    'igual',
    (tester) async {
      final container = await _pumpDebtsScreen(tester);
      final netBefore =
          (await container.read(
            patrimonioSnapshotProvider.future,
          )).todayValueUsdCents;
      final stageBefore = container
          .read(ledgerProjectionsProvider)
          .envelopeUsdBalance(
            (await container.read(
              catalogRepositoryProvider.future,
            )).getSystemEnvelope(EnvelopeRole.stage),
          );

      await tester.tap(find.byKey(const Key('debtAction_prestar_Pedro')));
      await tester.pumpAndSettle();

      final destinationChip = tester.widget<ChoiceChip>(
        find.byKey(const Key('moverDestinationChip_pedro')),
      );
      expect(destinationChip.selected, isTrue);

      await tester.tap(find.byKey(const Key('moverSourceChip_efectivo')));
      await tester.pump();
      await _enterAmount(tester, '20000');
      await tester.ensureVisible(find.byKey(const Key('quickAddSaveButton')));
      await tester.tap(find.byKey(const Key('quickAddSaveButton')));
      await tester.pumpAndSettle();

      final projections = container.read(ledgerProjectionsProvider);
      expect(projections.accountBalance(AccountId('efectivo')).usd, 80000);
      expect(projections.accountBalance(AccountId('pedro')).usd, 20000);

      final catalog = await container.read(catalogRepositoryProvider.future);
      final stageAfter = projections.envelopeUsdBalance(
        catalog.getSystemEnvelope(EnvelopeRole.stage),
      );
      expect(stageAfter, stageBefore);

      final netAfter =
          (await container.read(
            patrimonioSnapshotProvider.future,
          )).todayValueUsdCents;
      expect(netAfter, netBefore);

      expect(find.text('Pedro te debe \$200.00'), findsOneWidget);
    },
  );

  testWidgets(
    'Cobrar \$50 from Pedro to Efectivo after a \$200 Prestar: "Pedro te '
    'debe \$150.00"',
    (tester) async {
      await _pumpDebtsScreen(tester);

      await tester.tap(find.byKey(const Key('debtAction_prestar_Pedro')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('moverSourceChip_efectivo')));
      await tester.pump();
      await _enterAmount(tester, '20000');
      await tester.ensureVisible(find.byKey(const Key('quickAddSaveButton')));
      await tester.tap(find.byKey(const Key('quickAddSaveButton')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('debtAction_cobrar_Pedro')));
      await tester.pumpAndSettle();

      final sourceChip = tester.widget<ChoiceChip>(
        find.byKey(const Key('moverSourceChip_pedro')),
      );
      expect(sourceChip.selected, isTrue);

      await tester.tap(find.byKey(const Key('moverDestinationChip_efectivo')));
      await tester.pump();
      await _enterAmount(tester, '5000');
      await tester.ensureVisible(find.byKey(const Key('quickAddSaveButton')));
      await tester.tap(find.byKey(const Key('quickAddSaveButton')));
      await tester.pumpAndSettle();

      expect(find.text('Pedro te debe \$150.00'), findsOneWidget);
    },
  );

  testWidgets(
    'Condonar \$150 from Pedro choosing the envelope Comida: Pedro queda en '
    '\$0.00 y Comida baja \$150.00',
    (tester) async {
      final container = await _pumpDebtsScreen(tester);

      await tester.tap(find.byKey(const Key('debtAction_prestar_Pedro')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('moverSourceChip_efectivo')));
      await tester.pump();
      await _enterAmount(tester, '15000');
      await tester.ensureVisible(find.byKey(const Key('quickAddSaveButton')));
      await tester.tap(find.byKey(const Key('quickAddSaveButton')));
      await tester.pumpAndSettle();

      expect(find.text('Pedro te debe \$150.00'), findsOneWidget);

      await tester.tap(find.byKey(const Key('debtAction_condonar_Pedro')));
      await tester.pumpAndSettle();

      final gastoChip = tester.widget<ChoiceChip>(
        find.byKey(const Key('captureModeGasto')),
      );
      expect(gastoChip.selected, isTrue);

      await _enterAmount(tester, '15000');
      await tester.tap(find.byKey(const Key('envelopeChip_comida')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('quickAddSaveButton')));
      await tester.tap(find.byKey(const Key('quickAddSaveButton')));
      await tester.pumpAndSettle();

      final projections = container.read(ledgerProjectionsProvider);
      expect(projections.accountBalance(AccountId('pedro')).usd, 0);
      expect(projections.envelopeUsdBalance(EnvelopeId('comida')), -15000);

      expect(find.text('Pedro te debe \$0.00'), findsOneWidget);
    },
  );
}
