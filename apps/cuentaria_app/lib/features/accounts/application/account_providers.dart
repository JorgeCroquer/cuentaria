import 'package:contabilidad/application/catalog/archive_account.dart';
import 'package:contabilidad/application/catalog/create_account.dart';
import 'package:contabilidad/application/catalog/update_account.dart';
import 'package:contabilidad/application/ledger/factories/record_opening.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/composition_root.dart';
import '../../../providers/tasas_providers.dart';
import 'create_account_with_rate.dart';

/// Creates an Account and, when given an opening balance, posts it through
/// the existing [RecordOpening] factory against the Apertura envelope (#94).
/// The opening rate is also recorded as a parallel-rate observation in tasas
/// through [CreateAccountWithRate] — the app-shell composition seam (#112).
final createAccountProvider = FutureProvider<CreateAccountWithRate>((
  ref,
) async {
  final store = await ref.watch(eventStoreProvider.future);
  final catalog = await ref.watch(catalogRepositoryProvider.future);
  final projections = ref.watch(ledgerProjectionsProvider);
  final eventBus = ref.watch(eventBusProvider);
  final rateSeries = await ref.watch(rateSeriesProvider.future);

  final recordTransaction = RecordTransaction(
    store: store,
    projections: projections,
    eventBus: eventBus,
    validator: ReferentialIntegrityValidator(catalog),
  );
  final recordOpening = RecordOpening(
    record: recordTransaction,
    catalog: catalog,
    projections: projections,
  );

  return CreateAccountWithRate(
    createAccount: CreateAccount(
      catalog: catalog,
      recordOpening: recordOpening,
    ),
    rateSeries: rateSeries,
  );
});

/// Updates an Account's name and/or color tag.
final updateAccountProvider = FutureProvider<UpdateAccount>((ref) async {
  final catalog = await ref.watch(catalogRepositoryProvider.future);
  return UpdateAccount(catalog: catalog);
});

/// Archives an Account — Patrimonio already excludes archived accounts.
final archiveAccountProvider = FutureProvider<ArchiveAccount>((ref) async {
  final catalog = await ref.watch(catalogRepositoryProvider.future);
  return ArchiveAccount(catalog: catalog);
});
