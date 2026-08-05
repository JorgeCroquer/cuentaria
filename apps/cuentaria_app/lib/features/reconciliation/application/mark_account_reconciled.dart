import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:shared_kernel/shared_kernel.dart';

/// Stamps [AccountId]'s `lastReconciledAt` in the catalog (C3 slice 4, #150)
/// — called by every reconciliation path that actually posts something: the
/// absorbed path ([ReconcileUseCase]) and the routed Income/Expense path
/// (the sheet, since those post through the shared quick-add use cases,
/// which know nothing about reconciliation).
class MarkAccountReconciled {
  final CatalogRepository _catalog;

  MarkAccountReconciled({required CatalogRepository catalog})
    : _catalog = catalog;

  Future<void> call(AccountId accountId, DateTime timestamp) async {
    final account = _catalog.getAccount(accountId);
    if (account == null) return;
    await _catalog.saveAccount(account.withLastReconciledAt(timestamp));
  }
}
