import 'package:contabilidad/application/ledger/rebuild_projections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/composition_root.dart';

/// Startup sequence gating the ledger UI: acquire key → open DB → seed →
/// hydrate → replay. Key acquisition, DB open, migrations (which seed the
/// system envelopes) and catalog hydration all happen as a side effect of
/// resolving [eventStoreProvider] / [catalogRepositoryProvider]; this
/// function's own job is the projections replay (#46), which must run last.
Future<void> bootstrapSequence(Ref ref) async {
  final eventStore = await ref.read(eventStoreProvider.future);
  await ref.read(catalogRepositoryProvider.future);
  final projections = ref.read(ledgerProjectionsProvider);

  await RebuildProjections(
    store: eventStore,
    projections: projections,
  ).execute();
}

final bootstrapProvider = FutureProvider<void>(bootstrapSequence);
