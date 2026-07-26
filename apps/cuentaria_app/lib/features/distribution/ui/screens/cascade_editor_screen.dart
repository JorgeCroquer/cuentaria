import 'package:contabilidad/application/cascade/cascade.dart';
import 'package:contabilidad/application/cascade/cascade_step.dart';
import 'package:contabilidad/application/cascade/cascade_validator.dart';
import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_kernel/shared_kernel.dart';

import '../../../../providers/composition_root.dart';
import '../../../envelopes/application/envelopes_providers.dart';
import '../../application/distribution_providers.dart';
import '../widgets/cascade_step_form.dart';

String _formatUsdCents(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';

String _stepLabel(CascadeStep step, String envelopeName) => switch (step) {
  FixedStep(:final amountUsd) =>
    'Fixed ${_formatUsdCents(amountUsd)} → $envelopeName',
  FillToCapStep() => 'Fill to cap → $envelopeName',
  PercentOfRemainderStep(:final percent) =>
    '${(percent * Decimal.fromInt(100)).toStringAsFixed(0)}% of remainder → '
        '$envelopeName',
  CatchAllStep() => 'Catch-all → $envelopeName',
};

/// [ReorderableListView.onReorder] semantics: when moving an item down,
/// [newIndex] is the position in the list *after* [oldIndex] is removed.
List<CascadeStep> reorderCascadeSteps(
  List<CascadeStep> steps,
  int oldIndex,
  int newIndex,
) {
  final result = List<CascadeStep>.of(steps);
  if (oldIndex < newIndex) newIndex -= 1;
  final step = result.removeAt(oldIndex);
  result.insert(newIndex, step);
  return result;
}

/// Cascade editor (#96): an ordered, drag-reorderable list of steps —
/// target user Envelope + funding type. Persists through the existing
/// [CascadeRepository] (single LWW document); validation is the engine's
/// own [CascadeValidator] — surfaced here, not reimplemented.
class CascadeEditorScreen extends ConsumerStatefulWidget {
  const CascadeEditorScreen({super.key});

  @override
  ConsumerState<CascadeEditorScreen> createState() =>
      _CascadeEditorScreenState();
}

class _CascadeEditorScreenState extends ConsumerState<CascadeEditorScreen> {
  List<CascadeStep>? _steps;
  bool _isSaving = false;

  Future<void> _addStep(List<Envelope> envelopes) async {
    if (envelopes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create an envelope first.')),
      );
      return;
    }
    final step = await showDialog<CascadeStep>(
      context: context,
      builder: (context) => CascadeStepForm(envelopes: envelopes),
    );
    if (step != null) setState(() => _steps = [..._steps!, step]);
  }

  Future<void> _editStep(int index, List<Envelope> envelopes) async {
    final step = await showDialog<CascadeStep>(
      context: context,
      builder:
          (context) =>
              CascadeStepForm(envelopes: envelopes, existing: _steps![index]),
    );
    if (step != null) {
      setState(() {
        final updated = List<CascadeStep>.of(_steps!);
        updated[index] = step;
        _steps = updated;
      });
    }
  }

  void _removeStep(int index) {
    setState(() {
      final updated = List<CascadeStep>.of(_steps!)..removeAt(index);
      _steps = updated;
    });
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() => _steps = reorderCascadeSteps(_steps!, oldIndex, newIndex));
  }

  Future<void> _save(CascadeValidationResult validation) async {
    if (!validation.isValid) return;
    setState(() => _isSaving = true);
    final repo = await ref.read(cascadeRepositoryProvider.future);
    await repo.save(Cascade(steps: _steps!, updatedAt: DateTime.now()));
    ref.invalidate(savedCascadeProvider);
    ref.invalidate(distributionPreviewProvider);
    if (mounted) {
      setState(() => _isSaving = false);
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cascadeAsync = ref.watch(savedCascadeProvider);
    final catalogAsync = ref.watch(catalogRepositoryProvider);
    final envelopesAsync = ref.watch(userEnvelopesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Edit cascade')),
      body: cascadeAsync.when(
        data: (cascade) {
          _steps ??= cascade?.steps ?? [];
          return catalogAsync.when(
            data:
                (catalog) => envelopesAsync.when(
                  data: (envelopes) => _buildBody(catalog, envelopes),
                  loading:
                      () => const Center(child: CircularProgressIndicator()),
                  error:
                      (error, stackTrace) =>
                          Center(child: Text('Error: $error')),
                ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => Center(child: Text('Error: $error')),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('Error: $error')),
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('addCascadeStepButton'),
        onPressed: () => _addStep(envelopesAsync.value ?? []),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody(CatalogRepository catalog, List<Envelope> envelopes) {
    final steps = _steps!;
    final catalogMap = <EnvelopeId, Envelope>{
      for (final envelope in catalog.envelopes) envelope.id: envelope,
    };
    final validation = CascadeValidator.validate(
      cascade: Cascade(steps: steps, updatedAt: DateTime.now()),
      catalog: catalogMap,
    );

    return Column(
      children: [
        Expanded(
          child:
              steps.isEmpty
                  ? const Center(
                    child: Text(
                      'No steps yet. Add one to start building the cascade.',
                      key: Key('cascadeEmptyState'),
                    ),
                  )
                  : ReorderableListView(
                    onReorder: _onReorder,
                    buildDefaultDragHandles: false,
                    children: [
                      for (var i = 0; i < steps.length; i++)
                        ListTile(
                          key: Key('cascadeStep_$i'),
                          leading: ReorderableDragStartListener(
                            index: i,
                            key: Key('dragHandle_$i'),
                            child: const Icon(Icons.drag_handle),
                          ),
                          title: Text(
                            _stepLabel(
                              steps[i],
                              catalogMap[steps[i].envelopeId]?.name ??
                                  steps[i].envelopeId.value,
                            ),
                          ),
                          onTap: () => _editStep(i, envelopes),
                          trailing: IconButton(
                            key: Key('deleteCascadeStep_$i'),
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Remove',
                            onPressed: () => _removeStep(i),
                          ),
                        ),
                    ],
                  ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (validation.errors.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    validation.errors.join('\n'),
                    key: const Key('cascadeValidationErrors'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (validation.warnings.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    validation.warnings.join('\n'),
                    key: const Key('cascadeValidationWarnings'),
                  ),
                ),
              ElevatedButton(
                key: const Key('saveCascadeButton'),
                onPressed:
                    (!validation.isValid || _isSaving)
                        ? null
                        : () => _save(validation),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
