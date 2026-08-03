import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/domain/rate_calculator.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_kernel/shared_kernel.dart';

import '../../../../providers/composition_root.dart';
import '../../../../providers/ledger_providers.dart';
import '../../application/capture_providers.dart';
import '../amount_input_controller.dart';
import '../widgets/numeric_keypad.dart';

/// Opens the quick-add capture sheet (U1 slices 4-5, #97/#98) from a FAB
/// reachable on every tab.
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

String _formatUsdCents(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';

enum _CaptureMode { gasto, ingreso, mover }

/// Which side of the Mover two-sided form the user is currently typing —
/// the other side is derived (U1, #98).
enum _RateInputMode { receivedAmount, rate }

/// Amount-first capture sheet: numeric keypad active on open, Account and
/// Envelope as chips preselected from ledger history (last-used account,
/// most-frequent envelope), date defaulting to today. "Gasto" derives
/// USD-expense vs. realization from the paying Account's currency (#97);
/// "Ingreso" always lands in Stage (#98); "Mover" derives transfer vs.
/// P2P/FX conversion from whether the two Accounts share a currency (#98) —
/// the user never sees any of this taxonomy.
class QuickAddExpenseSheet extends ConsumerStatefulWidget {
  const QuickAddExpenseSheet({super.key});

  @override
  ConsumerState<QuickAddExpenseSheet> createState() =>
      _QuickAddExpenseSheetState();
}

class _QuickAddExpenseSheetState extends ConsumerState<QuickAddExpenseSheet> {
  _CaptureMode _mode = _CaptureMode.gasto;
  DateTime _date = DateTime.now();
  bool _isSaving = false;
  bool _defaultsApplied = false;
  String? _error;

  // Gasto
  final _amount = AmountInputController();
  final _noteController = TextEditingController();
  bool _noteExpanded = false;
  AccountId? _selectedAccountId;
  EnvelopeId? _selectedEnvelopeId;

  // Ingreso
  final _sourceController = TextEditingController();
  AccountId? _selectedIncomeAccountId;
  int? _incomeStageBalanceUsd;

  // Mover
  final _moverGivenAmount = AmountInputController();
  final _rateFieldController = TextEditingController();
  AccountId? _moverSourceAccountId;
  AccountId? _moverDestinationAccountId;
  _RateInputMode _rateInputMode = _RateInputMode.receivedAmount;

  @override
  void dispose() {
    _amount.dispose();
    _noteController.dispose();
    _sourceController.dispose();
    _moverGivenAmount.dispose();
    _rateFieldController.dispose();
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
    _selectedIncomeAccountId = _selectedAccountId;

    final moverPair = captureContext.lastUsedMoverPair;
    final accountIds = captureContext.accounts.map((a) => a.id).toSet();
    if (moverPair != null &&
        accountIds.contains(moverPair.sourceAccountId) &&
        accountIds.contains(moverPair.destinationAccountId)) {
      _moverSourceAccountId = moverPair.sourceAccountId;
      _moverDestinationAccountId = moverPair.destinationAccountId;
    }
  }

  Account? _accountById(QuickAddCaptureContext captureContext, AccountId? id) {
    if (id == null) return null;
    for (final account in captureContext.accounts) {
      if (account.id == id) return account;
    }
    return null;
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

  Future<void> _saveGasto(Account account) async {
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
        note: _noteController.text.trim(),
      );

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveIncome(Account account) async {
    if (!_amount.isValid) return;

    setState(() {
      _error = null;
      _isSaving = true;
    });

    try {
      final catalog = await ref.read(catalogRepositoryProvider.future);
      final recordIncome = await ref.read(recordIncomeProvider.future);
      final deviceId = await ref.read(deviceIdProvider.future);

      await recordIncome(
        eventId: EventId(DateTime.now().microsecondsSinceEpoch.toString()),
        deviceId: deviceId,
        accountId: account.id,
        amount: Money(
          amount: _amount.amountMinorUnits,
          currency: account.nativeCurrency,
        ),
        source: _sourceController.text.trim(),
        occurredAt: DomainTimestamp(_date.toUtc()),
      );

      final projections = ref.read(ledgerProjectionsProvider);
      final stageId = catalog.getSystemEnvelope(EnvelopeRole.stage);
      final stageBalance = projections.envelopeUsdBalance(stageId);

      ref.invalidate(quickAddCaptureContextProvider);

      if (mounted) {
        setState(() {
          _incomeStageBalanceUsd = stageBalance;
          _amount.clear();
          _sourceController.clear();
        });
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  BigInt? _parseDecimalCents(String text) {
    final value = Decimal.tryParse(text.trim());
    if (value == null) return null;
    return (value * Decimal.fromInt(100)).round().toBigInt();
  }

  String _formatCentsAsAmount(BigInt cents) {
    final decimal =
        (Decimal.fromBigInt(cents) / Decimal.fromInt(100)).toDecimal();
    return decimal.toStringAsFixed(2);
  }

  Money? _explicitReceivedAmount(Account destinationAccount) {
    if (_rateInputMode != _RateInputMode.receivedAmount) return null;
    final cents = _parseDecimalCents(_rateFieldController.text);
    if (cents == null) return null;
    return Money(amount: cents, currency: destinationAccount.nativeCurrency);
  }

  Decimal? _explicitRate() {
    if (_rateInputMode != _RateInputMode.rate) return null;
    return Decimal.tryParse(_rateFieldController.text.trim());
  }

  /// The value the other field would show, derived live (U1, #98) — powers
  /// the inline preview and pre-fills the field when the toggle switches,
  /// so switching modes never loses information.
  String? _deriveOtherFieldText(Account destinationAccount) {
    if (!_moverGivenAmount.isValid) return null;
    if (_rateInputMode == _RateInputMode.receivedAmount) {
      final received = _explicitReceivedAmount(destinationAccount);
      if (received == null) return null;
      final rate = RateCalculator.deriveRate(
        usdCents: _moverGivenAmount.amountMinorUnits,
        nativeCents: received.amount,
      );
      return rate.toStringAsFixed(2);
    }
    final rate = _explicitRate();
    if (rate == null) return null;
    final nativeCents = RateCalculator.deriveNativeCents(
      usdCents: _moverGivenAmount.amountMinorUnits,
      rate: rate,
    );
    return _formatCentsAsAmount(nativeCents);
  }

  void _toggleRateInputMode(
    _RateInputMode newMode,
    Account destinationAccount,
  ) {
    if (newMode == _rateInputMode) return;
    final derived = _deriveOtherFieldText(destinationAccount);
    setState(() {
      _rateInputMode = newMode;
      _rateFieldController.text = derived ?? '';
    });
  }

  bool _moverCanSave(QuickAddCaptureContext captureContext) {
    final source = _accountById(captureContext, _moverSourceAccountId);
    final destination = _accountById(
      captureContext,
      _moverDestinationAccountId,
    );
    if (source == null || destination == null) return false;
    if (source.id == destination.id) return false;
    if (!_moverGivenAmount.isValid) return false;
    if (source.nativeCurrency == destination.nativeCurrency) return true;
    return _explicitReceivedAmount(destination) != null ||
        _explicitRate() != null;
  }

  Future<void> _saveMover(Account source, Account destination) async {
    setState(() {
      _error = null;
      _isSaving = true;
    });

    try {
      final useCase = await ref.read(quickAddMoverUseCaseProvider.future);
      final deviceId = await ref.read(deviceIdProvider.future);
      final sameCurrency = source.nativeCurrency == destination.nativeCurrency;

      await useCase(
        eventId: EventId(DateTime.now().microsecondsSinceEpoch.toString()),
        deviceId: deviceId,
        sourceAccountId: source.id,
        destinationAccountId: destination.id,
        givenAmount: Money(
          amount: _moverGivenAmount.amountMinorUnits,
          currency: source.nativeCurrency,
        ),
        receivedAmount:
            sameCurrency ? null : _explicitReceivedAmount(destination),
        rate: sameCurrency ? null : _explicitRate(),
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
    return AnimatedBuilder(
      animation: Listenable.merge([_amount, _moverGivenAmount]),
      builder: (context, _) => _buildReactiveBody(captureContext),
    );
  }

  Widget _buildReactiveBody(QuickAddCaptureContext captureContext) {
    final selectedAccount = _accountById(captureContext, _selectedAccountId);
    final selectedIncomeAccount = _accountById(
      captureContext,
      _selectedIncomeAccountId,
    );
    final moverSourceAccount = _accountById(
      captureContext,
      _moverSourceAccountId,
    );
    final moverDestinationAccount = _accountById(
      captureContext,
      _moverDestinationAccountId,
    );

    final canSave = switch (_mode) {
      _CaptureMode.gasto =>
        !_isSaving &&
            _amount.isValid &&
            selectedAccount != null &&
            _selectedEnvelopeId != null,
      _CaptureMode.ingreso =>
        !_isSaving && _amount.isValid && selectedIncomeAccount != null,
      _CaptureMode.mover => !_isSaving && _moverCanSave(captureContext),
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ChoiceChip(
                key: const Key('captureModeGasto'),
                label: const Text('Gasto'),
                selected: _mode == _CaptureMode.gasto,
                onSelected: (_) => setState(() => _mode = _CaptureMode.gasto),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                key: const Key('captureModeIngreso'),
                label: const Text('Ingreso'),
                selected: _mode == _CaptureMode.ingreso,
                onSelected: (_) => setState(() => _mode = _CaptureMode.ingreso),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                key: const Key('captureModeMover'),
                label: const Text('Mover'),
                selected: _mode == _CaptureMode.mover,
                onSelected: (_) => setState(() => _mode = _CaptureMode.mover),
              ),
            ],
          ),
          const SizedBox(height: 16),
          switch (_mode) {
            _CaptureMode.gasto => _buildGastoBody(captureContext),
            _CaptureMode.ingreso => _buildIngresoBody(captureContext),
            _CaptureMode.mover => _buildMoverBody(
              captureContext,
              moverSourceAccount,
              moverDestinationAccount,
            ),
          },
          const SizedBox(height: 16),
          TextButton(
            key: const Key('quickAddDateField'),
            onPressed: _pickDate,
            child: Text(_formatDate(_date)),
          ),
          if (_mode == _CaptureMode.gasto)
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
          ElevatedButton(
            key: const Key('quickAddSaveButton'),
            onPressed:
                !canSave
                    ? null
                    : () {
                      switch (_mode) {
                        case _CaptureMode.gasto:
                          _saveGasto(selectedAccount!);
                        case _CaptureMode.ingreso:
                          _saveIncome(selectedIncomeAccount!);
                        case _CaptureMode.mover:
                          _saveMover(
                            moverSourceAccount!,
                            moverDestinationAccount!,
                          );
                      }
                    },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _buildGastoBody(QuickAddCaptureContext captureContext) {
    return Column(
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
                      (_) => setState(() => _selectedEnvelopeId = envelope.id),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildIngresoBody(QuickAddCaptureContext captureContext) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_incomeStageBalanceUsd != null)
          ListTile(
            key: const Key('incomeDistributeCta'),
            title: Text(
              'Sin asignar: ${_formatUsdCents(_incomeStageBalanceUsd!)} '
              '— Distribuir',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              final router = GoRouter.of(context);
              Navigator.of(context).pop();
              router.push('/distribute');
            },
          ),
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
        TextField(
          key: const Key('incomeSourceField'),
          controller: _sourceController,
          decoration: const InputDecoration(labelText: 'Cliente / fuente'),
        ),
        if (captureContext.previousIncomeSources.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final source in captureContext.previousIncomeSources)
                ActionChip(
                  key: Key('incomeSourceSuggestion_$source'),
                  label: Text(source),
                  onPressed:
                      () => setState(() => _sourceController.text = source),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        if (captureContext.accounts.isEmpty)
          const Text('No accounts yet.')
        else
          Wrap(
            spacing: 8,
            children: [
              for (final account in captureContext.accounts)
                ChoiceChip(
                  key: Key('incomeAccountChip_${account.id.value}'),
                  label: Text(account.name),
                  selected: account.id == _selectedIncomeAccountId,
                  onSelected:
                      (_) =>
                          setState(() => _selectedIncomeAccountId = account.id),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildMoverBody(
    QuickAddCaptureContext captureContext,
    Account? sourceAccount,
    Account? destinationAccount,
  ) {
    final differentCurrency =
        sourceAccount != null &&
        destinationAccount != null &&
        sourceAccount.nativeCurrency != destinationAccount.nativeCurrency;

    return Column(
      key: const Key('moverStep1'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Desde'),
        if (captureContext.accounts.isEmpty)
          const Text('No accounts yet.')
        else
          Wrap(
            spacing: 8,
            children: [
              for (final account in captureContext.accounts)
                ChoiceChip(
                  key: Key('moverSourceChip_${account.id.value}'),
                  label: Text(account.name),
                  selected: account.id == _moverSourceAccountId,
                  onSelected:
                      (_) => setState(() => _moverSourceAccountId = account.id),
                ),
            ],
          ),
        const SizedBox(height: 16),
        const Text('Hacia'),
        if (captureContext.accounts.isEmpty)
          const Text('No accounts yet.')
        else
          Wrap(
            spacing: 8,
            children: [
              for (final account in captureContext.accounts)
                ChoiceChip(
                  key: Key('moverDestinationChip_${account.id.value}'),
                  label: Text(account.name),
                  selected: account.id == _moverDestinationAccountId,
                  onSelected:
                      (_) => setState(
                        () => _moverDestinationAccountId = account.id,
                      ),
                ),
            ],
          ),
        const SizedBox(height: 16),
        Center(
          child: AnimatedBuilder(
            animation: _moverGivenAmount,
            builder:
                (context, _) => Text(
                  _moverGivenAmount.displayText,
                  key: const Key('amountDisplay'),
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
          ),
        ),
        const SizedBox(height: 8),
        Center(child: NumericKeypad(controller: _moverGivenAmount)),
        if (differentCurrency) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              ChoiceChip(
                key: const Key('moverToggleReceived'),
                label: const Text('Monto recibido'),
                selected: _rateInputMode == _RateInputMode.receivedAmount,
                onSelected:
                    (_) => _toggleRateInputMode(
                      _RateInputMode.receivedAmount,
                      destinationAccount,
                    ),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                key: const Key('moverToggleRate'),
                label: const Text('Tasa aplicada'),
                selected: _rateInputMode == _RateInputMode.rate,
                onSelected:
                    (_) => _toggleRateInputMode(
                      _RateInputMode.rate,
                      destinationAccount,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('moverRateInputField'),
            controller: _rateFieldController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText:
                  _rateInputMode == _RateInputMode.receivedAmount
                      ? 'Monto recibido (${destinationAccount.nativeCurrency.value})'
                      : 'Tasa aplicada '
                          '(${destinationAccount.nativeCurrency.value}/USD)',
            ),
            onChanged: (_) => setState(() {}),
          ),
          Builder(
            builder: (context) {
              final derived = _deriveOtherFieldText(destinationAccount);
              if (derived == null) return const SizedBox.shrink();
              final label =
                  _rateInputMode == _RateInputMode.receivedAmount
                      ? 'Tasa: $derived '
                          '${destinationAccount.nativeCurrency.value}/USD'
                      : 'Recibes: $derived '
                          '${destinationAccount.nativeCurrency.value}';
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(label, key: const Key('moverDerivedPreview')),
              );
            },
          ),
        ],
      ],
    );
  }
}
