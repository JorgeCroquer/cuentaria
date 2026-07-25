import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/catalog/models/envelope_appearance.dart';
import 'package:contabilidad/application/catalog/models/funding_target.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_kernel/shared_kernel.dart';

import '../../../../providers/composition_root.dart';
import '../../../../ui/theme/app_icons.dart';
import '../../../../ui/theme/app_theme.dart';
import '../../../patrimonio/application/patrimonio_providers.dart';
import '../../application/envelopes_providers.dart';

enum _TargetKind { none, cap, goalLine }

String _targetKindLabel(_TargetKind kind) => switch (kind) {
  _TargetKind.none => 'None',
  _TargetKind.cap => 'Cap',
  _TargetKind.goalLine => 'Goal line',
};

/// Create/edit form for one user Envelope (U1 slice 2, #95): name, icon
/// (curated subset, [AppIcons]), color ([AppColors] palette) and an optional
/// Funding Target — none / Cap / GoalLine. `envelopeId == null` is create
/// mode; otherwise the existing Envelope is loaded and updated in place.
/// No app UI links to a System Envelope here, but a direct/deep link still
/// could — [build] guards that case by refusing to render the form for any
/// hydrated Envelope with `role != EnvelopeRole.none`, so it can't be saved
/// over and corrupt the system Envelope's name/meta.
class EnvelopeEditScreen extends ConsumerStatefulWidget {
  const EnvelopeEditScreen({super.key, this.envelopeId});

  final EnvelopeId? envelopeId;

  @override
  ConsumerState<EnvelopeEditScreen> createState() => _EnvelopeEditScreenState();
}

class _EnvelopeEditScreenState extends ConsumerState<EnvelopeEditScreen> {
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();

  String? _iconId;
  int? _colorIndex;
  _TargetKind _targetKind = _TargetKind.none;
  DateTime? _dueDate;
  String? _error;
  bool _isSaving = false;
  bool _hydrated = false;
  Envelope? _existing;

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _hydrate(Envelope envelope) {
    _existing = envelope;
    _nameController.text = envelope.name;
    _iconId = envelope.appearance.iconId;
    _colorIndex = envelope.appearance.colorIndex;
    switch (envelope.target) {
      case NoTarget():
        _targetKind = _TargetKind.none;
      case Cap(:final amountUsd):
        _targetKind = _TargetKind.cap;
        _amountController.text = (amountUsd / 100).toStringAsFixed(2);
      case GoalLine(:final amountUsd, :final dueDate):
        _targetKind = _TargetKind.goalLine;
        _amountController.text = (amountUsd / 100).toStringAsFixed(2);
        _dueDate = dueDate;
    }
  }

  Future<void> _save(CatalogRepository catalog) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name.');
      return;
    }

    FundingTarget target;
    if (_targetKind == _TargetKind.none) {
      target = const NoTarget();
    } else {
      final dollars = double.tryParse(_amountController.text);
      if (dollars == null || dollars <= 0) {
        setState(() => _error = 'Enter an amount greater than zero.');
        return;
      }
      final amountUsd = (dollars * 100).round();
      target =
          _targetKind == _TargetKind.cap
              ? Cap(amountUsd: amountUsd)
              : GoalLine(amountUsd: amountUsd, dueDate: _dueDate);
    }

    setState(() {
      _error = null;
      _isSaving = true;
    });

    final id =
        widget.envelopeId ??
        EnvelopeId('env-${DateTime.now().microsecondsSinceEpoch}');
    final envelope = Envelope(
          id: id,
          name: name,
          role: EnvelopeRole.none,
          isArchived: _existing?.isArchived ?? false,
          updatedAt: DateTime.now(),
          meta: _existing?.meta,
        )
        .withTarget(target)
        .withAppearance(
          EnvelopeAppearance(iconId: _iconId, colorIndex: _colorIndex),
        );

    await catalog.saveEnvelope(envelope);
    ref.invalidate(userEnvelopesProvider);
    ref.invalidate(patrimonioSnapshotProvider);

    if (mounted) context.pop();
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(catalogRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.envelopeId == null ? 'New envelope' : 'Edit envelope',
        ),
      ),
      body: catalogAsync.when(
        data: (catalog) {
          if (widget.envelopeId != null && !_hydrated) {
            final existing = catalog.getEnvelope(widget.envelopeId!);
            if (existing != null) _hydrate(existing);
            _hydrated = true;
          }
          if (_existing != null && _existing!.role != EnvelopeRole.none) {
            return _buildSystemEnvelopeNotice();
          }
          return _buildForm(catalog);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('Error: $error')),
      ),
    );
  }

  Widget _buildSystemEnvelopeNotice() {
    return const Center(
      key: Key('systemEnvelopeNotice'),
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Text(
          'System envelopes cannot be edited.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildForm(CatalogRepository catalog) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        TextFormField(
          key: const Key('nameField'),
          controller: _nameController,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        const SizedBox(height: AppSpacing.lg),
        const Text('Icon'),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            for (final entry in AppIcons.catalog.entries)
              IconButton(
                key: Key('icon_${entry.key}'),
                isSelected: _iconId == entry.key,
                icon: Icon(entry.value),
                style: IconButton.styleFrom(
                  backgroundColor:
                      _iconId == entry.key
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                ),
                onPressed: () => setState(() => _iconId = entry.key),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        const Text('Color'),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            for (var i = 0; i < AppColors.palette.length; i++)
              InkWell(
                key: Key('color_$i'),
                onTap: () => setState(() => _colorIndex = i),
                customBorder: const CircleBorder(),
                child: CircleAvatar(
                  backgroundColor: AppColors.palette[i],
                  radius: _colorIndex == i ? 16 : 12,
                  child:
                      _colorIndex == i
                          ? const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 16,
                          )
                          : null,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        const Text('Funding target'),
        DropdownButton<_TargetKind>(
          key: const Key('targetKindDropdown'),
          value: _targetKind,
          items: [
            for (final kind in _TargetKind.values)
              DropdownMenuItem(
                value: kind,
                child: Text(_targetKindLabel(kind)),
              ),
          ],
          onChanged: (kind) {
            if (kind != null) setState(() => _targetKind = kind);
          },
        ),
        if (_targetKind != _TargetKind.none) ...[
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            key: const Key('targetAmountField'),
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount (USD)'),
          ),
        ],
        if (_targetKind == _TargetKind.goalLine) ...[
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            key: const Key('dueDateButton'),
            onPressed: _pickDueDate,
            child: Text(
              _dueDate == null
                  ? 'No due date'
                  : 'Due ${_dueDate!.toLocal().toString().split(' ').first}',
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        ElevatedButton(
          key: const Key('saveEnvelopeButton'),
          onPressed: _isSaving ? null : () => _save(catalog),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
