import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:cuentaria_app/features/patrimonio/application/patrimonio_providers.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:cuentaria_app/providers/ledger_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';

void main() {
  group('netWorthUsdProvider', () {
    test('excludes archived accounts from the sum', () async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      final catalog = await container.read(catalogRepositoryProvider.future);
      final deviceId = await container.read(deviceIdProvider.future);
      final recordIncome = await container.read(recordIncomeProvider.future);
      final liveAccountId = catalog.accountIds.first;

      final archivedAccount = Account(
        id: AccountId('archived-1'),
        name: 'Old wallet',
        nativeCurrency: CurrencyCode('USD'),
        isArchived: true,
        updatedAt: DateTime.now(),
      );
      await catalog.saveAccount(archivedAccount);

      await recordIncome(
        eventId: EventId('evt-archived'),
        deviceId: deviceId,
        accountId: archivedAccount.id,
        amount: Money(amount: BigInt.from(9900), currency: CurrencyCode('USD')),
        source: 'Manual entry',
      );
      await recordIncome(
        eventId: EventId('evt-live'),
        deviceId: deviceId,
        accountId: liveAccountId,
        amount: Money(amount: BigInt.from(2500), currency: CurrencyCode('USD')),
        source: 'Manual entry',
      );

      final netWorth = await container.read(netWorthUsdProvider.future);
      expect(netWorth, 2500);
    });

    test('invalidates itself when a transaction is recorded', () async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      final initial = await container.read(netWorthUsdProvider.future);
      expect(initial, 0);

      final catalog = await container.read(catalogRepositoryProvider.future);
      final deviceId = await container.read(deviceIdProvider.future);
      final recordIncome = await container.read(recordIncomeProvider.future);

      await recordIncome(
        eventId: EventId('evt-reactive'),
        deviceId: deviceId,
        accountId: catalog.accountIds.first,
        amount: Money(amount: BigInt.from(1500), currency: CurrencyCode('USD')),
        source: 'Manual entry',
      );

      final updated = await container.read(netWorthUsdProvider.future);
      expect(updated, 1500);
    });
  });
}
