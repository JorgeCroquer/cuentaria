import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_kernel/shared_kernel.dart';

import '../../../../providers/composition_root.dart';
import '../../application/capture_providers.dart';
import '../amount_input_controller.dart';
import '../widgets/numeric_keypad.dart';

/// Opens the quick-add expense sheet (U1 slice 4, #97) from a FAB reachable
/// on every tab.
Future<void> showQuickAddExpenseSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const QuickAddExpenseSheet(),
  );
}

String _formatDate(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

/// Amount-first capture sheet: numeric keypad active on open, Account and
/// Envelope as chips preselected from ledger history (last-used account,
/// most-frequent envelope), date defaulting to today. Only "Gasto" is
/// functional this slice — the app derives USD-expense vs. realization from
/// the paying Account's currency inside [QuickAddExpenseUseCase]; the user
/// never sees that taxonomy.
class QuickAddExpenseSheet extends ConsumerStatefulWidget {
  const QuickAddExpenseSheet({super.key});

  @override
  ConsumerState<QuickAddExpenseSheet> createState() =>
      _QuickAddExpenseSheetState();
}

class _QuickAddExpenseSheetState extends ConsumerState<QuickAddExpenseSheet> {
  final _amount = AmountInputController();
  final _noteController = TextEditingController();
  DateTime _date = DateTime.now();
  bool _noteExpanded = false;
  bool _isSaving = false;
  bool _defaultsApplied = false;
  String? _error;
  AccountId? _selectedAccountId;
  EnvelopeId? _selectedEnvelopeId;

  @override
  void dispose() {
    _amount.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _applyDefaults(QuickAddCaptureContext captureContext) {
    if (_defaultsApplied) return;
    _defaultsApplied = true;
    _selectedAccountId =
        captureContext.lastUsedAccountId ??
        (captureContext.accounts.isEmpty
            ? null
            : captureContext.accounts.first.id);
    _selectedEnvelopeId =
        captureContext.envelopes.isEmpty
            ? null
            : captureContext.envelopes.first.id;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save(Account account) async {
    final envelopeId = _selectedEnvelopeId;
    if (envelopeId == null || !_amount.isValid) return;

    setState(() {
      _error = null;
      _isSaving = true;
    });

    try {
      final useCase = await ref.read(quickAddExpenseUseCaseProvider.future);
      final deviceId = await ref.read(deviceIdProvider.future);

      await useCase(
        eventId: EventId(DateTime.now().microsecondsSinceEpoch.toString()),
        deviceId: deviceId,
        accountId: account.id,
        envelopeId: envelopeId,
        amount: Money(
          amount: _amount.amountMinorUnits,
          currency: account.nativeCurrency,
        ),
        occurredAt: DomainTimestamp(_date.toUtc()),
      );

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final captureContextAsync = ref.watch(quickAddCaptureContextProvider);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: captureContextAsync.when(
          data: (captureContext) {
            _applyDefaults(captureContext);
            return _buildBody(captureContext);
          },
          loading:
              () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
          error:
              (error, stackTrace) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Error: $error'),
              ),
        ),
      ),
    );
  }

  Widget _buildBody(QuickAddCaptureContext captureContext) {
    Account? selectedAccount;
    if (captureContext.accounts.isNotEmpty) {
      selectedAccount = captureContext.accounts.firstWhere(
        (a) => a.id == _selectedAccountId,
        orElse: () => captureContext.accounts.first,
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: AnimatedBuilder(
              animation: _amount,
              builder:
                  (context, _) => Text(
                    _amount.displayText,
                    key: const Key('amountDisplay'),
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
            ),
          ),
          const SizedBox(height: 8),
          Center(child: NumericKeypad(controller: _amount)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ChoiceChip(
                key: const Key('captureModeGasto'),
                label: const Text('Gasto'),
                selected: true,
                onSelected: (_) {},
              ),
              const SizedBox(width: 8),
              const ChoiceChip(
                key: Key('captureModeIngreso'),
                label: Text('Ingreso'),
                selected: false,
                onSelected: null,
              ),
              const SizedBox(width: 8),
              const ChoiceChip(
                key: Key('captureModeMover'),
                label: Text('Mover'),
                selected: false,
                onSelected: null,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (captureContext.accounts.isEmpty)
            const Text('No accounts yet.')
          else
            Wrap(
              spacing: 8,
              children: [
                for (final account in captureContext.accounts)
                  ChoiceChip(
                    key: Key('accountChip_${account.id.value}'),
                    label: Text(account.name),
                    selected: account.id == _selectedAccountId,
                    onSelected:
                        (_) => setState(() => _selectedAccountId = account.id),
                  ),
              ],
            ),
          const SizedBox(height: 16),
          if (captureContext.envelopes.isEmpty)
            const Text('No envelopes yet.')
          else
            Wrap(
              spacing: 8,
              children: [
                for (final envelope in captureContext.envelopes)
                  ChoiceChip(
                    key: Key('envelopeChip_${envelope.id.value}'),
                    label: Text(envelope.name),
                    selected: envelope.id == _selectedEnvelopeId,
                    onSelected:
                        (_) =>
                            setState(() => _selectedEnvelopeId = envelope.id),
                  ),
              ],
            ),
          const SizedBox(height: 16),
          TextButton(
            key: const Key('quickAddDateField'),
            onPressed: _pickDate,
            child: Text(_formatDate(_date)),
          ),
          if (!_noteExpanded)
            TextButton(
              key: const Key('quickAddNoteToggle'),
              onPressed: () => setState(() => _noteExpanded = true),
              child: const Text('Add note'),
            )
          else
            TextField(
              key: const Key('quickAddNoteField'),
              controller: _noteController,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          AnimatedBuilder(
            animation: _amount,
            builder:
                (context, _) => ElevatedButton(
                  key: const Key('quickAddSaveButton'),
                  onPressed:
                      (_isSaving || !_amount.isValid || selectedAccount == null)
                          ? null
                          : () => _save(selectedAccount!),
                  child: const Text('Save'),
                ),
          ),
        ],
      ),
    );
  }
}
