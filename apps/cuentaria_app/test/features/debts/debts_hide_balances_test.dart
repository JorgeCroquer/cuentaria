import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/domain/posting.dart';
import 'package:contabilidad/domain/posting_target.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:contabilidad/domain/transaction_metadata.dart';
import 'package:cuentaria_app/features/debts/ui/screens/debts_screen.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';

/// #333: balances hidden by default means Deudas shows no digit either —
/// not in the global net, nor in a person's headline/currency-leg line.
void main() {
  testWidgets('shows no digit anywhere while balances are hidden (#333)', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [isWebProvider.overrideWithValue(true)],
    );
    addTearDown(container.dispose);

    final catalog = await container.read(catalogRepositoryProvider.future);
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

    final deviceId = await container.read(deviceIdProvider.future);
    final projections = container.read(ledgerProjectionsProvider);
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

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DebtsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final globalText =
        tester.widget<Text>(find.byKey(const Key('debtsGlobalAmount'))).data!;
    expect(RegExp(r'\d').hasMatch(globalText), isFalse);

    final headlineText =
        tester.widget<Text>(find.textContaining('Pedro te debe')).data!;
    expect(RegExp(r'\d').hasMatch(headlineText), isFalse);

    final legText = tester.widget<Text>(find.textContaining('USD:')).data!;
    expect(RegExp(r'\d').hasMatch(legText), isFalse);
  });
}
