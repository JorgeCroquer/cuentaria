import 'package:shared_kernel/shared_kernel.dart';

import 'catalog_repository.dart';
import 'exceptions.dart';
import 'models/account.dart';

/// Archives an Account by setting `isArchived` (#94). Patrimonio already
/// filters archived accounts out of its totals (see [PatrimonioEngine]) —
/// there is no delete path for accounts, mirroring how system envelopes are
/// never deleted either.
class ArchiveAccount {
  final CatalogRepository _catalog;

  ArchiveAccount({required CatalogRepository catalog}) : _catalog = catalog;

  Future<void> call(AccountId id) async {
    final existing = _catalog.getAccount(id);
    if (existing == null) {
      throw TargetNotFound('Account not found: $id');
    }

    await _catalog.saveAccount(
      Account(
        id: existing.id,
        name: existing.name,
        nativeCurrency: existing.nativeCurrency,
        provider: existing.provider,
        isArchived: true,
        updatedAt: DateTime.now().toUtc(),
        meta: existing.meta,
      ),
    );
  }
}
