import 'package:contabilidad/application/cascade/cascade_step.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:shared_kernel/shared_kernel.dart';

enum _StepKind { fixed, fillToCap, percentOfRemainder, catchAll }

String _stepKindLabel(_StepKind kind) => switch (kind) {
  _StepKind.fixed => 'Monto fijo',
  _StepKind.fillToCap => 'Llenar hasta el tope',
  _StepKind.percentOfRemainder => '% del restante',
  _StepKind.catchAll => 'Resto',
};

_StepKind _kindOf(CascadeStep step) => switch (step) {
  FixedStep() => _StepKind.fixed,
  FillToCapStep() => _StepKind.fillToCap,
  PercentOfRemainderStep() => _StepKind.percentOfRemainder,
  CatchAllStep() => _StepKind.catchAll,
};

/// Create/edit form for one [CascadeStep] (#96 cascade editor): target
/// Envelope + funding type, with the type-specific amount/percent field.
/// Pops with the built [CascadeStep], or null if cancelled. Validation of
/// the resulting cascade (catch-all position, ranges, envelope usability)
/// is the engine's own [CascadeValidator] — this form only builds the step.
class CascadeStepForm extends StatefulWidget {
  const CascadeStepForm({super.key, required this.envelopes, this.existing});

  final List<Envelope> envelopes;
  final CascadeStep? existing;

  @override
  State<CascadeStepForm> createState() => _CascadeStepFormState();
}

class _CascadeStepFormState extends State<CascadeStepForm> {
  final _amountController = TextEditingController();
  final _percentController = TextEditingController();

  EnvelopeId? _envelopeId;
  _StepKind _kind = _StepKind.fixed;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _envelopeId =
        existing?.envelopeId ??
        (widget.envelopes.isEmpty ? null : widget.envelopes.first.id);
    if (existing != null) {
      _kind = _kindOf(existing);
      switch (existing) {
        case FixedStep(:final amountUsd):
          _amountController.text = (amountUsd / 100).toStringAsFixed(2);
        case PercentOfRemainderStep(:final percent):
          _percentController.text = (percent * Decimal.fromInt(100)).toString();
        case FillToCapStep():
        case CatchAllStep():
          break;
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _percentController.dispose();
    super.dispose();
  }

  void _save() {
    final envelopeId = _envelopeId;
    if (envelopeId == null) return;

    final CascadeStep step;
    switch (_kind) {
      case _StepKind.fixed:
        final dollars =
            Decimal.tryParse(_amountController.text) ?? Decimal.zero;
        step = CascadeStep.fixed(
          envelopeId: envelopeId,
          amountUsd:
              (dollars * Decimal.fromInt(100)).round().toBigInt().toInt(),
        );
      case _StepKind.fillToCap:
        step = CascadeStep.fillToCap(envelopeId: envelopeId);
      case _StepKind.percentOfRemainder:
        // Straight to Decimal, never via double (money/rate values are never
        // double, per the ledger's hard rule) — `double.tryParse` here
        // corrupted most real-world inputs (e.g. 99.99 -> 0.9998999...).
        final pct = Decimal.tryParse(_percentController.text) ?? Decimal.zero;
        step = CascadeStep.percentOfRemainder(
          envelopeId: envelopeId,
          percent: pct * Decimal.parse('0.01'),
          base: PercentBase.remainder,
        );
      case _StepKind.catchAll:
        step = CascadeStep.catchAll(envelopeId: envelopeId);
    }

    Navigator.of(context).pop(step);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Agregar paso' : 'Editar paso'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButton<EnvelopeId>(
            key: const Key('stepEnvelopeDropdown'),
            value: _envelopeId,
            items: [
              for (final envelope in widget.envelopes)
                DropdownMenuItem(
                  value: envelope.id,
                  child: Text(envelope.name),
                ),
            ],
            onChanged: (id) => setState(() => _envelopeId = id),
          ),
          const SizedBox(height: 8),
          DropdownButton<_StepKind>(
            key: const Key('stepFundingTypeDropdown'),
            value: _kind,
            items: [
              for (final kind in _StepKind.values)
                DropdownMenuItem(
                  value: kind,
                  child: Text(_stepKindLabel(kind)),
                ),
            ],
            onChanged: (kind) {
              if (kind != null) setState(() => _kind = kind);
            },
          ),
          if (_kind == _StepKind.fixed) ...[
            const SizedBox(height: 8),
            TextField(
              key: const Key('stepAmountField'),
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Monto (USD)'),
            ),
          ],
          if (_kind == _StepKind.percentOfRemainder) ...[
            const SizedBox(height: 8),
            TextField(
              key: const Key('stepPercentField'),
              controller: _percentController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Porcentaje (0-100)',
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: const Key('cancelStepButton'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          key: const Key('saveStepButton'),
          onPressed: _envelopeId == null ? null : _save,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
