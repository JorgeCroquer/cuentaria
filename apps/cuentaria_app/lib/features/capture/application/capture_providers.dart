import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/ledger/factories/record_acquisition_conversion.dart';
import 'package:contabilidad/application/ledger/factories/record_income.dart';
import 'package:contabilidad/application/ledger/factories/record_realization.dart';
import 'package:contabilidad/application/ledger/factories/record_transfer.dart';
import 'package:contabilidad/application/ledger/factories/record_usd_expense.dart';
import 'package:contabilidad/application/ledger/quick_add_defaults.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_kernel/shared_kernel.dart';

import '../../../providers/composition_root.dart';
import '../../../providers/tasas_providers.dart';
import '../../envelopes/application/envelopes_providers.dart';
import 'quick_add_expense_use_case.dart';
import 'quick_add_income_use_case.dart';
import 'quick_add_mover_use_case.dart';

/// Last-used Account + Envelopes-by-frequency, both derived from
/// [EventStore.queryLog] with no preferences store (U1, #97).
final quickAddDefaultsProvider = FutureProvider<QuickAddDefaults>((ref) async {
  final store = await ref.watch(eventStoreProvider.future);
  return QuickAddDefaults(store);
});

final quickAddExpenseUseCaseProvider = FutureProvider<QuickAddExpenseUseCase>((
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

  return QuickAddExpenseUseCase(
    recordUsdExpense: RecordUsdExpense(
      record: recordTransaction,
      catalog: catalog,
    ),
    recordRealization: RecordRealization(
      record: recordTransaction,
      catalog: catalog,
      projections: projections,
    ),
    catalog: catalog,
    rateSeries: rateSeries,
  );
});

final quickAddIncomeUseCaseProvider = FutureProvider<QuickAddIncomeUseCase>((
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

  return QuickAddIncomeUseCase(
    recordIncome: RecordIncome(record: recordTransaction, catalog: catalog),
    catalog: catalog,
    rateSeries: rateSeries,
  );
});

final quickAddMoverUseCaseProvider = FutureProvider<QuickAddMoverUseCase>((
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

  return QuickAddMoverUseCase(
    recordTransfer: RecordTransfer(
      record: recordTransaction,
      catalog: catalog,
      projections: projections,
    ),
    recordAcquisitionConversion: RecordAcquisitionConversion(
      record: recordTransaction,
      catalog: catalog,
    ),
    recordRealization: RecordRealization(
      record: recordTransaction,
      catalog: catalog,
      projections: projections,
    ),
    catalog: catalog,
    rateSeries: rateSeries,
  );
});

/// Everything the quick-add sheet needs to render its chips with smart
/// defaults, precomputed once so the widget only deals with a single
/// [AsyncValue]. [accounts] is every non-archived account, used to resolve a
/// selection by id regardless of mode; [regularAccounts]/[debtAccounts]
/// split it for the pickers (#208): Gasto/Ingreso only offer
/// [regularAccounts], Mover offers both.
class QuickAddCaptureContext {
  final List<Account> accounts;
  final List<Account> regularAccounts;
  final List<Account> debtAccounts;
  final List<Envelope> envelopes;
  final AccountId? lastUsedAccountId;
  final List<String> previousIncomeSources;
  final MoverPair? lastUsedMoverPair;

  QuickAddCaptureContext({
    required this.accounts,
    required this.regularAccounts,
    required this.debtAccounts,
    required this.envelopes,
    required this.lastUsedAccountId,
    required this.previousIncomeSources,
    required this.lastUsedMoverPair,
  });
}

final quickAddCaptureContextProvider = FutureProvider<QuickAddCaptureContext>((
  ref,
) async {
  ref.watch(catalogRevisionProvider);
  final catalog = await ref.watch(catalogRepositoryProvider.future);
  final defaults = await ref.watch(quickAddDefaultsProvider.future);
  final userEnvelopes = await ref.watch(userEnvelopesProvider.future);

  final accounts =
      catalog.accounts.where((a) => !a.isArchived).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
  final regularAccounts = accounts.where((a) => !a.isDebtAccount).toList();
  final debtAccounts = accounts.where((a) => a.isDebtAccount).toList();

  final frequencyOrder = await defaults.envelopesByFrequency();
  final envelopesById = {for (final e in userEnvelopes) e.id: e};
  final envelopes = [
    for (final id in frequencyOrder)
      if (envelopesById.containsKey(id)) envelopesById[id]!,
    for (final e in userEnvelopes)
      if (!frequencyOrder.contains(e.id)) e,
  ];

  return QuickAddCaptureContext(
    accounts: accounts,
    regularAccounts: regularAccounts,
    debtAccounts: debtAccounts,
    envelopes: envelopes,
    lastUsedAccountId: await defaults.lastUsedAccount(),
    previousIncomeSources: await defaults.previousIncomeSources(),
    lastUsedMoverPair: await defaults.lastUsedMoverPair(),
  );
});
