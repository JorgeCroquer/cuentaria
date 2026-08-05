import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/infrastructure/catalog/in_memory_catalog_repository.dart';
import 'package:cuentaria_app/features/reconciliation/application/mark_account_reconciled.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';

void main() {
  group('MarkAccountReconciled', () {
    test('stamps lastReconciledAt on the account in the catalog', () async {
      final catalog = InMemoryCatalogRepository();
      final accountId = AccountId('acc-1');
      await catalog.saveAccount(
        Account(
          id: accountId,
          name: 'Wallet',
          nativeCurrency: CurrencyCode('USD'),
          isArchived: false,
          updatedAt: DateTime.utc(2024, 1, 1),
        ),
      );

      final markReconciled = MarkAccountReconciled(catalog: catalog);
      await markReconciled(accountId, DateTime.utc(2024, 3, 5));

      expect(
        catalog.getAccount(accountId)!.lastReconciledAt,
        DateTime.utc(2024, 3, 5),
      );
    });

    test('does nothing for an unknown account', () async {
      final catalog = InMemoryCatalogRepository();
      final markReconciled = MarkAccountReconciled(catalog: catalog);

      await markReconciled(AccountId('missing'), DateTime.utc(2024, 3, 5));

      expect(catalog.getAccount(AccountId('missing')), isNull);
    });
  });
}
