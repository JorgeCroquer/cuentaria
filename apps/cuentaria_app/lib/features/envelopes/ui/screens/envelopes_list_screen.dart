import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/catalog/models/funding_target.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../providers/composition_root.dart';
import '../../../../ui/theme/app_icons.dart';
import '../../../../ui/theme/app_theme.dart';
import '../../application/envelopes_providers.dart';

String _formatUsdCents(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';

String? _targetSummary(FundingTarget target) => switch (target) {
  NoTarget() => null,
  Cap(:final amountUsd) => 'Tope: ${_formatUsdCents(amountUsd)}',
  GoalLine(:final amountUsd, :final dueDate) =>
    dueDate == null
        ? 'Meta: ${_formatUsdCents(amountUsd)}'
        : 'Meta: ${_formatUsdCents(amountUsd)} para '
            '${dueDate.toLocal().toString().split(' ').first}',
};

/// Management screen for user Envelopes (U1 slice 2, #95): create, edit and
/// archive name/icon/color/target. System Envelopes (Stage, Diferencial,
/// Ajustes, Apertura) never appear here — [userEnvelopesProvider] filters
/// them out at the source.
class EnvelopesListScreen extends ConsumerWidget {
  const EnvelopesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final envelopesAsync = ref.watch(userEnvelopesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Sobres')),
      body: envelopesAsync.when(
        data: (envelopes) {
          if (envelopes.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Sin sobres aún. Crea uno para empezar a financiar una '
                  'meta.',
                  key: Key('envelopesEmptyState'),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            children: [
              for (final envelope in envelopes)
                _EnvelopeListTile(envelope: envelope),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error:
            (error, stackTrace) =>
                Center(child: Text('No se pudo cargar: $error')),
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('createEnvelopeButton'),
        onPressed: () => context.push('/envelopes/new'),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _EnvelopeListTile extends ConsumerWidget {
  const _EnvelopeListTile({required this.envelope});

  final Envelope envelope;

  Future<void> _archive(WidgetRef ref) async {
    final catalog = await ref.read(catalogRepositoryProvider.future);
    await catalog.saveEnvelope(
      Envelope(
        id: envelope.id,
        name: envelope.name,
        role: envelope.role,
        isArchived: true,
        updatedAt: DateTime.now(),
        meta: envelope.meta,
      ),
    );
    ref.invalidate(userEnvelopesProvider);
    ref.read(catalogRevisionProvider.notifier).bump();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = envelope.appearance;
    final summary = _targetSummary(envelope.target);
    final color =
        appearance.colorIndex == null
            ? null
            : AppColors.palette[appearance.colorIndex! %
                AppColors.palette.length];

    return ListTile(
      key: Key('envelope_${envelope.id.value}'),
      leading: Icon(AppIcons.iconFor(appearance.iconId), color: color),
      title: Text(envelope.name),
      subtitle: summary == null ? null : Text(summary),
      onTap: () => context.push('/envelopes/${envelope.id.value}/edit'),
      trailing: IconButton(
        key: Key('archiveEnvelope_${envelope.id.value}'),
        icon: const Icon(Icons.archive_outlined),
        tooltip: 'Archivar',
        onPressed: () => _archive(ref),
      ),
    );
  }
}
