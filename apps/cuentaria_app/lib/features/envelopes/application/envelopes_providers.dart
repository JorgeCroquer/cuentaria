import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/composition_root.dart';

/// Non-archived, user-created Envelopes (role == none) for the management
/// screen (#95) — system Envelopes (Stage/Diferencial/Ajustes/Apertura) are
/// never editable or creatable here, so they are filtered out at the source.
final userEnvelopesProvider = FutureProvider<List<Envelope>>((ref) async {
  final catalog = await ref.watch(catalogRepositoryProvider.future);
  final envelopes =
      catalog.envelopes
          .where((e) => e.role == EnvelopeRole.none && !e.isArchived)
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
  return envelopes;
});
