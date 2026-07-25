import 'package:decimal/decimal.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:uuid/uuid.dart';

import 'catalog_repository.dart';
import 'models/account.dart';
import '../ledger/factories/record_opening.dart';

/// Creates an Account and, when [call] is given a non-zero [openingBalance],
/// posts it against the Apertura system envelope through the existing
/// [RecordOpening] factory (#94) — never invents money, only wires an
/// account creation to the ledger's own opening path.
class CreateAccount {
  final CatalogRepository _catalog;
  final RecordOpening _recordOpening;
  final Uuid _uuid;

  CreateAccount({
    required CatalogRepository catalog,
    required RecordOpening recordOpening,
    Uuid uuid = const Uuid(),
  }) : _catalog = catalog,
       _recordOpening = recordOpening,
       _uuid = uuid;

  Future<AccountId> call({
    required String name,
    required CurrencyCode nativeCurrency,
    String? colorHex,
    Money? openingBalance,
    int? openingBalanceUsd,
    Decimal? openingBalanceRate,
    required EventId eventId,
    required String deviceId,
  }) async {
    final id = AccountId(_uuid.v4());
    await _catalog.saveAccount(
      Account(
        id: id,
        name: name,
        nativeCurrency: nativeCurrency,
        isArchived: false,
        updatedAt: DateTime.now().toUtc(),
        meta: colorHex != null ? {'color': colorHex} : null,
      ),
    );

    if (openingBalance != null && openingBalance.amount != BigInt.zero) {
      await _recordOpening(
        eventId: eventId,
        deviceId: deviceId,
        accountId: id,
        nativeAmount: openingBalance,
        amountUsd: openingBalanceUsd,
        rate: openingBalanceRate,
      );
    }

    return id;
  }
}
