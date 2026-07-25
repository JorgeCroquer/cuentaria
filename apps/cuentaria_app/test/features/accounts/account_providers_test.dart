import 'package:contabilidad/application/catalog/exceptions.dart';
import 'package:cuentaria_app/features/accounts/application/account_providers.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';

void main() {
  group('account providers', () {
    test('createAccountProvider creates an account and posts its opening '
        'balance to Apertura', () async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      final createAccount = await container.read(createAccountProvider.future);
      final projections = container.read(ledgerProjectionsProvider);
      final catalog = await container.read(catalogRepositoryProvider.future);

      final id = await createAccount(
        name: 'Bancamiga',
        nativeCurrency: CurrencyCode('USD'),
        colorHex: '#FF5500',
        openingBalance: Money(
          amount: BigInt.from(20000),
          currency: CurrencyCode('USD'),
        ),
        eventId: EventId('evt-provider-1'),
        deviceId: 'test-device',
      );

      expect(catalog.getAccount(id)?.name, 'Bancamiga');
      expect(catalog.getAccount(id)?.colorHex, '#FF5500');
      expect(projections.accountBalance(id).usd, 20000);
    });

    test('updateAccountProvider updates the color', () async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      final createAccount = await container.read(createAccountProvider.future);
      final updateAccount = await container.read(updateAccountProvider.future);
      final catalog = await container.read(catalogRepositoryProvider.future);

      final id = await createAccount(
        name: 'Binance',
        nativeCurrency: CurrencyCode('USD'),
        eventId: EventId('evt-provider-2'),
        deviceId: 'test-device',
      );

      await updateAccount(id: id, colorHex: '#00FF00');

      expect(catalog.getAccount(id)?.colorHex, '#00FF00');
    });

    test('archiveAccountProvider archives the account', () async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      final createAccount = await container.read(createAccountProvider.future);
      final archiveAccount = await container.read(
        archiveAccountProvider.future,
      );
      final catalog = await container.read(catalogRepositoryProvider.future);

      final id = await createAccount(
        name: 'BdV',
        nativeCurrency: CurrencyCode('VES'),
        eventId: EventId('evt-provider-3'),
        deviceId: 'test-device',
      );

      await archiveAccount(id);

      expect(catalog.getAccount(id)?.isArchived, isTrue);
    });

    test('archiveAccountProvider throws for an unknown account', () async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      final archiveAccount = await container.read(
        archiveAccountProvider.future,
      );

      await expectLater(
        () => archiveAccount(AccountId('missing')),
        throwsA(isA<TargetNotFound>()),
      );
    });
  });
}
