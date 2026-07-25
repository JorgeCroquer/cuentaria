import 'package:contabilidad/application/ledger/factories/record_reversal.dart';
import 'package:contabilidad/application/record_transaction.dart';
import 'package:contabilidad/application/ledger/referential_integrity_validator.dart';
import 'package:contabilidad/domain/transaction.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_kernel/shared_kernel.dart';

import '../../../providers/composition_root.dart';

/// Chronological transaction feed for the Movements screen (#99), newest
/// first. Re-subscribes to [eventBusProvider] and invalidates itself on
/// every recorded [Transaction] — mirrors [patrimonioSnapshotProvider]'s
/// reactivity pattern so the list never needs a manual refresh.
final movementsListProvider = FutureProvider<List<Transaction>>((ref) async {
  final eventBus = ref.watch(eventBusProvider);
  final subscription = eventBus.stream.listen((event) {
    if (event is Transaction) ref.invalidateSelf();
  });
  ref.onDispose(subscription.cancel);

  final store = await ref.watch(eventStoreProvider.future);
  final log = await store.queryLog();
  return [...log]..sort(
    (a, b) =>
        b.metadata.occurredAt.value.compareTo(a.metadata.occurredAt.value),
  );
});

/// One transaction by [EventId], for the detail screen.
final transactionProvider = FutureProvider.family<Transaction?, EventId>((
  ref,
  eventId,
) async {
  final store = await ref.watch(eventStoreProvider.future);
  return store.get(eventId);
});

/// Whether the transaction identified by [EventId] already has a reversal
/// appended against it — powers the double-reversal guard (#99).
final reversalStatusProvider = FutureProvider.family<bool, EventId>((
  ref,
  eventId,
) async {
  final store = await ref.watch(eventStoreProvider.future);
  return store.hasReversal(eventId);
});

/// Appends an exact negation of an original transaction through the
/// existing [RecordReversal] factory, wired with the composition-root
/// adapters — no new domain logic.
final recordReversalProvider = FutureProvider<RecordReversal>((ref) async {
  final store = await ref.watch(eventStoreProvider.future);
  final catalog = await ref.watch(catalogRepositoryProvider.future);
  final projections = ref.watch(ledgerProjectionsProvider);
  final eventBus = ref.watch(eventBusProvider);

  final recordTransaction = RecordTransaction(
    store: store,
    projections: projections,
    eventBus: eventBus,
    validator: ReferentialIntegrityValidator(catalog),
  );

  return RecordReversal(record: recordTransaction, store: store);
});
