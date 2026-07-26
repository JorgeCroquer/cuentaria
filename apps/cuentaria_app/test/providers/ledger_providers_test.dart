import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:cuentaria_app/providers/ledger_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';

void main() {
  group('recordIncomeProvider', () {
    test(
      'records a movement that updates account and envelope balances',
      () async {
        final container = ProviderContainer(
          overrides: [isWebProvider.overrideWithValue(true)],
        );
        addTearDown(container.dispose);

        final catalog = await container.read(catalogRepositoryProvider.future);
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
        final stageId = catalog.getSystemEnvelope(EnvelopeRole.stage);

        final recordIncome = await container.read(recordIncomeProvider.future);
        await recordIncome(
          eventId: EventId('evt-test-1'),
          deviceId: 'test-device',
          accountId: accountId,
          amount: Money(
            amount: BigInt.from(2500),
            currency: CurrencyCode('USD'),
          ),
          source: 'Manual entry',
        );

        final projections = container.read(ledgerProjectionsProvider);
        expect(projections.accountBalance(accountId).usd, 2500);
        expect(projections.envelopeUsdBalance(stageId), 2500);
      },
    );
  });
}
