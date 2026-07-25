import 'package:contabilidad/application/catalog/exceptions.dart';
import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/update_account.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:test/test.dart';

void main() {
  group('UpdateAccount', () {
    late InMemoryCatalogRepository catalog;
    late UpdateAccount updateAccount;
    late AccountId accountId;

    setUp(() async {
      catalog = InMemoryCatalogRepository();
      updateAccount = UpdateAccount(catalog: catalog);
      accountId = AccountId('acc-1');
      await catalog.saveAccount(
        Account(
          id: accountId,
          name: 'Bancamiga',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.utc(2024, 1, 1),
          meta: {'color': '#OLD'},
        ),
      );
    });

    test('updates the name, leaving currency and color untouched', () async {
      await updateAccount(id: accountId, name: 'Bancamiga USD');

      final updated = catalog.getAccount(accountId)!;
      expect(updated.name, 'Bancamiga USD');
      expect(updated.nativeCurrency, CurrencyCode('USD'));
      expect(updated.colorHex, '#OLD');
    });

    test('updates the color, storing it in meta', () async {
      await updateAccount(id: accountId, colorHex: '#00FF00');

      final updated = catalog.getAccount(accountId)!;
      expect(updated.colorHex, '#00FF00');
      expect(updated.name, 'Bancamiga');
    });

    test('throws TargetNotFound for an unknown account', () async {
      await expectLater(
        () => updateAccount(id: AccountId('missing'), name: 'X'),
        throwsA(isA<TargetNotFound>()),
      );
    });
  });
}
