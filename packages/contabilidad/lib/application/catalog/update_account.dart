import 'package:shared_kernel/shared_kernel.dart';

import 'catalog_repository.dart';
import 'exceptions.dart';
import 'models/account.dart';

/// Updates an Account's name and/or color tag (#94). Currency is immutable
/// and never accepted here — `nativeCurrency` is fixed at creation.
class UpdateAccount {
  final CatalogRepository _catalog;

  UpdateAccount({required CatalogRepository catalog}) : _catalog = catalog;

  Future<void> call({
    required AccountId id,
    String? name,
    String? colorHex,
  }) async {
    final existing = _catalog.getAccount(id);
    if (existing == null) {
      throw TargetNotFound('Account not found: $id');
    }

    final updatedMeta = Map<String, dynamic>.from(existing.meta ?? {});
    if (colorHex != null) {
      updatedMeta['color'] = colorHex;
    }

    await _catalog.saveAccount(
      Account(
        id: existing.id,
        name: name ?? existing.name,
        nativeCurrency: existing.nativeCurrency,
        provider: existing.provider,
        isArchived: existing.isArchived,
        updatedAt: DateTime.now().toUtc(),
        meta: updatedMeta.isEmpty ? null : updatedMeta,
      ),
    );
  }
}
