import 'package:contabilidad/application/catalog/archive_account.dart';
import 'package:contabilidad/application/catalog/exceptions.dart';
import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:test/test.dart';

void main() {
  group('ArchiveAccount', () {
    late InMemoryCatalogRepository catalog;
    late ArchiveAccount archiveAccount;
    late AccountId accountId;

    setUp(() async {
      catalog = InMemoryCatalogRepository();
      archiveAccount = ArchiveAccount(catalog: catalog);
      accountId = AccountId('acc-1');
      await catalog.saveAccount(
        Account(
          id: accountId,
          name: 'Old wallet',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.utc(2024, 1, 1),
          meta: {'color': '#AAAAAA'},
        ),
      );
    });

    test('sets isArchived to true, keeping name/currency/color', () async {
      await archiveAccount(accountId);

      final archived = catalog.getAccount(accountId)!;
      expect(archived.isArchived, isTrue);
      expect(archived.name, 'Old wallet');
      expect(archived.nativeCurrency, CurrencyCode('USD'));
      expect(archived.colorHex, '#AAAAAA');
    });

    test('throws TargetNotFound for an unknown account', () async {
      await expectLater(
        () => archiveAccount(AccountId('missing')),
        throwsA(isA<TargetNotFound>()),
      );
    });
  });
}
