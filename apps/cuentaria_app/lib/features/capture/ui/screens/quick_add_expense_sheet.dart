import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/application/ledger/exceptions.dart' as ledger;
import 'package:contabilidad/domain/rate_calculator.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/domain/rate_resolver.dart';

import '../../../../providers/composition_root.dart';
import '../../../../providers/tasas_providers.dart';
import '../../../patrimonio/ui/screens/patrimonio_screen.dart';
import '../../application/capture_providers.dart';
import '../../application/rate_exceptions.dart';
import '../amount_input_controller.dart';
import '../widgets/numeric_keypad.dart';

/// Opens the quick-add capture sheet (U1 slices 4-5, #97/#98) from a FAB
/// reachable on every tab. The Deudas screen's Prestar/Cobrar/Condonar
/// actions (#208) reuse this same entry point, passing one of the
/// preselected-account params to land on Mover or Gasto with the Debt
/// Account already picked.
Future<void> showQuickAddExpenseSheet(
  BuildContext context, {
  AccountId? preselectedGastoAccountId,
  AccountId? preselectedMoverSourceAccountId,
  AccountId? preselectedMoverDestinationAccountId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder:
        (context) => QuickAddExpenseSheet(
          preselectedGastoAccountId: preselectedGastoAccountId,
          preselectedMoverSourceAccountId: preselectedMoverSourceAccountId,
          preselectedMoverDestinationAccountId:
              preselectedMoverDestinationAccountId,
        ),
  );
}

String _formatDate(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

String _formatUsdCents(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';

/// Maps domain exceptions to Spanish, user-actionable copy so the capture
/// UI never surfaces a raw `toString()` of a domain type (#121). This is a
/// safety net, not the primary path: the Save button is gated on
/// [latestParaleloRateProvider] so a missing rate is caught before the tap,
/// not after (#119).
String _userFacingErrorMessage(Object error) {
  if (error is RateNotAvailable) {
    return 'No hay tasa registrada para Bs. Regístrala desde Patrimonio '
        '(icono de tasas) y vuelve a intentar.';
  }
  if (error is ledger.UsdOnlyOperation) {
    return 'Esta operación aún no está disponible para cuentas en esta '
        'moneda.';
  }
  debugPrint('QuickAddExpenseSheet: unmapped error: $error');
  return 'No se pudo guardar el movimiento.';
}

const _monthAbbreviations = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

String _formatShortDate(DateTime date) =>
    '${date.day} ${_monthAbbreviations[date.month - 1]}';

bool _isToday(DateTime date) {
  final now = DateTime.now();
  return date.year == now.year &&
      date.month == now.month &&
      date.day == now.day;
}

/// Human-readable provenance for a resolved Rate (#165): the announcement
/// names the source, not just the number (ADR-0018 "la app siempre anuncia
/// con qué valoró").
String _sourceLabel(String source) => switch (source) {
  'binancep2p:ask' => 'Binance P2P',
  'dolarapi:paralelo' => 'DolarApi',
  _ => 'manual',
};

/// A manual entry always reads "hoy" — the user just typed it. An automatic
/// source reads how long ago it synced, since it refreshes periodically
/// through the day (ADR-0020) rather than at the moment of the transaction.
String _recency(DateTime observedLocal, String source) {
  if (source == 'manual:paralelo') return 'hoy';
  final hours = DateTime.now().difference(observedLocal).inHours;
  return 'hace $hours h';
}

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
  const QuickAddExpenseSheet({
    super.key,
    this.preselectedGastoAccountId,
    this.preselectedMoverSourceAccountId,
    this.preselectedMoverDestinationAccountId,
  });

  final AccountId? preselectedGastoAccountId;
  final AccountId? preselectedMoverSourceAccountId;
  final AccountId? preselectedMoverDestinationAccountId;

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
  void initState() {
    super.initState();
    if (widget.preselectedMoverSourceAccountId != null ||
        widget.preselectedMoverDestinationAccountId != null) {
      _mode = _CaptureMode.mover;
    }
  }

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
        widget.preselectedGastoAccountId ??
        captureContext.lastUsedAccountId ??
        (captureContext.regularAccounts.isEmpty
            ? null
            : captureContext.regularAccounts.first.id);
    _selectedEnvelopeId =
        captureContext.envelopes.isEmpty
            ? null
            : captureContext.envelopes.first.id;
    _selectedIncomeAccountId = _selectedAccountId;

    _moverSourceAccountId = widget.preselectedMoverSourceAccountId;
    _moverDestinationAccountId = widget.preselectedMoverDestinationAccountId;
    if (_moverSourceAccountId == null && _moverDestinationAccountId == null) {
      final moverPair = captureContext.lastUsedMoverPair;
      final accountIds = captureContext.accounts.map((a) => a.id).toSet();
      if (moverPair != null &&
          accountIds.contains(moverPair.sourceAccountId) &&
          accountIds.contains(moverPair.destinationAccountId)) {
        _moverSourceAccountId = moverPair.sourceAccountId;
        _moverDestinationAccountId = moverPair.destinationAccountId;
      }
    }
  }

  Account? _accountById(QuickAddCaptureContext captureContext, AccountId? id) {
    if (id == null) return null;
    for (final account in captureContext.accounts) {
      if (account.id == id) return account;
    }
    return null;
  }

  /// Same-named accounts in different currencies (e.g. two "Bancamiga"
  /// wallets) render as identical chips without this — the currency is the
  /// only thing that disambiguates them on screen (#118).
  String _accountChipLabel(Account account) =>
      '${account.name} · ${account.nativeCurrency.value}';

  /// Whether Save must stay disabled because [currency] is foreign and no
  /// parallel Rate Observation exists yet for it (ADR-0018 §7) — applies to
  /// both Gasto and Ingreso, since both value a foreign-currency Account
  /// against the same observation.
  bool _rateBlocked(CurrencyCode currency) {
    if (currency == CurrencyCode('USD')) return false;
    final rateAsync = ref.watch(latestParaleloRateProvider(currency));
    return rateAsync.maybeWhen(
      data: (observation) => observation == null,
      orElse: () => false,
    );
  }

  void _openRecordRatesDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => const RecordRatesDialog(),
    );
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
      setState(() => _error = _userFacingErrorMessage(e));
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
      final useCase = await ref.read(quickAddIncomeUseCaseProvider.future);
      final deviceId = await ref.read(deviceIdProvider.future);

      await useCase(
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
      setState(() => _error = _userFacingErrorMessage(e));
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

  bool _sourceIsUsd(Account sourceAccount) =>
      sourceAccount.nativeCurrency == CurrencyCode('USD');

  /// The non-USD side of the pair — the rate is always quoted
  /// native-per-USD (CONTEXT.md Hard Rule), and "native" is whichever
  /// Account isn't USD, not necessarily the destination (#116).
  CurrencyCode _foreignCurrencyOfPair(
    Account sourceAccount,
    Account destinationAccount,
  ) =>
      _sourceIsUsd(sourceAccount)
          ? destinationAccount.nativeCurrency
          : sourceAccount.nativeCurrency;

  /// The value the other field would show, derived live (U1, #98) — powers
  /// the inline preview and pre-fills the field when the toggle switches,
  /// so switching modes never loses information. Which side is USD depends
  /// on the direction of the Mover (#116): USD -> foreign treats given as
  /// USD and received as native; foreign -> USD treats given as native and
  /// received as USD, so the roles — not the field positions — pick the
  /// [RateCalculator] call.
  String? _deriveOtherFieldText(
    Account sourceAccount,
    Account destinationAccount,
  ) {
    if (!_moverGivenAmount.isValid) return null;
    final sourceIsUsd = _sourceIsUsd(sourceAccount);
    if (_rateInputMode == _RateInputMode.receivedAmount) {
      final received = _explicitReceivedAmount(destinationAccount);
      if (received == null) return null;
      final rate =
          sourceIsUsd
              ? RateCalculator.deriveRate(
                usdCents: _moverGivenAmount.amountMinorUnits,
                nativeCents: received.amount,
              )
              : RateCalculator.deriveRate(
                usdCents: received.amount,
                nativeCents: _moverGivenAmount.amountMinorUnits,
              );
      return rate.toStringAsFixed(2);
    }
    final rate = _explicitRate();
    if (rate == null) return null;
    if (sourceIsUsd) {
      final nativeCents = RateCalculator.deriveNativeCents(
        usdCents: _moverGivenAmount.amountMinorUnits,
        rate: rate,
      );
      return _formatCentsAsAmount(nativeCents);
    }
    final usdCents = RateCalculator.deriveUsdCents(
      nativeCents: _moverGivenAmount.amountMinorUnits,
      rate: rate,
    );
    return _formatCentsAsAmount(usdCents);
  }

  void _toggleRateInputMode(
    _RateInputMode newMode,
    Account sourceAccount,
    Account destinationAccount,
  ) {
    if (newMode == _rateInputMode) return;
    final derived = _deriveOtherFieldText(sourceAccount, destinationAccount);
    setState(() {
      _rateInputMode = newMode;
      _rateFieldController.text = derived ?? '';
    });
  }

  /// Whether [candidate] can be picked as the Mover destination given the
  /// current [source]: a foreign source paired with a *different* foreign
  /// destination isn't modeled by any factory (ADR-0018 §5), so that chip
  /// is disabled rather than left to fail after Save (#116).
  bool _moverDestinationSelectable(Account? source, Account candidate) {
    if (source == null) return true;
    if (_sourceIsUsd(source)) return true;
    if (candidate.nativeCurrency == CurrencyCode('USD')) return true;
    return candidate.nativeCurrency == source.nativeCurrency;
  }

  /// How much of the typed Mover amount exceeds the known native balance of
  /// a non-USD same-currency [source] (ADR-0018 §3) — `null` when the pair
  /// doesn't apply (different currencies, USD, or nothing typed yet) or the
  /// balance already covers it, since only the excess ever gets valued
  /// against a rate.
  BigInt? _moverForeignExcess(Account? source, Account? destination) {
    if (source == null || destination == null) return null;
    if (source.nativeCurrency != destination.nativeCurrency) return null;
    if (source.nativeCurrency == CurrencyCode('USD')) return null;
    if (!_moverGivenAmount.isValid) return null;

    final balance = ref
        .read(ledgerProjectionsProvider)
        .accountBalance(source.id);
    final available =
        balance.native.amount < BigInt.zero
            ? BigInt.zero
            : balance.native.amount;
    final amount = _moverGivenAmount.amountMinorUnits;
    if (amount <= available) return null;
    return amount - available;
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
      setState(() => _error = _userFacingErrorMessage(e));
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
            _selectedEnvelopeId != null &&
            !_rateBlocked(selectedAccount.nativeCurrency),
      _CaptureMode.ingreso =>
        !_isSaving &&
            _amount.isValid &&
            selectedIncomeAccount != null &&
            !_rateBlocked(selectedIncomeAccount.nativeCurrency),
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
    final selectedAccount = _accountById(captureContext, _selectedAccountId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: AnimatedBuilder(
            animation: _amount,
            builder:
                (context, _) => _AmountDisplay(
                  text: _amount.displayText,
                  currency: selectedAccount?.nativeCurrency,
                ),
          ),
        ),
        const SizedBox(height: 8),
        Center(child: NumericKeypad(controller: _amount)),
        if (selectedAccount != null &&
            selectedAccount.nativeCurrency != CurrencyCode('USD'))
          _RateValuationAnnouncement(
            currency: selectedAccount.nativeCurrency,
            onRegisterRate: _openRecordRatesDialog,
          ),
        const SizedBox(height: 16),
        if (captureContext.regularAccounts.isEmpty)
          const Text('No accounts yet.')
        else
          Wrap(
            spacing: 8,
            children: [
              for (final account in captureContext.regularAccounts)
                ChoiceChip(
                  key: Key('accountChip_${account.id.value}'),
                  label: Text(_accountChipLabel(account)),
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
    final selectedAccount = _accountById(
      captureContext,
      _selectedIncomeAccountId,
    );
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
                (context, _) => _AmountDisplay(
                  text: _amount.displayText,
                  currency: selectedAccount?.nativeCurrency,
                ),
          ),
        ),
        const SizedBox(height: 8),
        Center(child: NumericKeypad(controller: _amount)),
        if (selectedAccount != null &&
            selectedAccount.nativeCurrency != CurrencyCode('USD'))
          _RateValuationAnnouncement(
            currency: selectedAccount.nativeCurrency,
            onRegisterRate: _openRecordRatesDialog,
          ),
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
        if (captureContext.regularAccounts.isEmpty)
          const Text('No accounts yet.')
        else
          Wrap(
            spacing: 8,
            children: [
              for (final account in captureContext.regularAccounts)
                ChoiceChip(
                  key: Key('incomeAccountChip_${account.id.value}'),
                  label: Text(_accountChipLabel(account)),
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
        else ...[
          Wrap(
            spacing: 8,
            children: [
              for (final account in captureContext.regularAccounts)
                ChoiceChip(
                  key: Key('moverSourceChip_${account.id.value}'),
                  label: Text(_accountChipLabel(account)),
                  selected: account.id == _moverSourceAccountId,
                  onSelected:
                      (_) => setState(() {
                        _moverSourceAccountId = account.id;
                        final currentDestination = _accountById(
                          captureContext,
                          _moverDestinationAccountId,
                        );
                        if (currentDestination != null &&
                            !_moverDestinationSelectable(
                              account,
                              currentDestination,
                            )) {
                          _moverDestinationAccountId = null;
                        }
                      }),
                ),
            ],
          ),
          if (captureContext.debtAccounts.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Deudas'),
            Wrap(
              spacing: 8,
              children: [
                for (final account in captureContext.debtAccounts)
                  ChoiceChip(
                    key: Key('moverSourceChip_${account.id.value}'),
                    label: Text(_accountChipLabel(account)),
                    selected: account.id == _moverSourceAccountId,
                    onSelected:
                        (_) => setState(() {
                          _moverSourceAccountId = account.id;
                          final currentDestination = _accountById(
                            captureContext,
                            _moverDestinationAccountId,
                          );
                          if (currentDestination != null &&
                              !_moverDestinationSelectable(
                                account,
                                currentDestination,
                              )) {
                            _moverDestinationAccountId = null;
                          }
                        }),
                  ),
              ],
            ),
          ],
        ],
        const SizedBox(height: 16),
        const Text('Hacia'),
        if (captureContext.accounts.isEmpty)
          const Text('No accounts yet.')
        else ...[
          Wrap(
            spacing: 8,
            children: [
              for (final account in captureContext.regularAccounts)
                ChoiceChip(
                  key: Key('moverDestinationChip_${account.id.value}'),
                  label: Text(_accountChipLabel(account)),
                  selected: account.id == _moverDestinationAccountId,
                  onSelected:
                      !_moverDestinationSelectable(sourceAccount, account)
                          ? null
                          : (_) => setState(
                            () => _moverDestinationAccountId = account.id,
                          ),
                ),
            ],
          ),
          if (captureContext.debtAccounts.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Deudas'),
            Wrap(
              spacing: 8,
              children: [
                for (final account in captureContext.debtAccounts)
                  ChoiceChip(
                    key: Key('moverDestinationChip_${account.id.value}'),
                    label: Text(_accountChipLabel(account)),
                    selected: account.id == _moverDestinationAccountId,
                    onSelected:
                        !_moverDestinationSelectable(sourceAccount, account)
                            ? null
                            : (_) => setState(
                              () => _moverDestinationAccountId = account.id,
                            ),
                  ),
              ],
            ),
          ],
        ],
        const SizedBox(height: 16),
        Center(
          child: AnimatedBuilder(
            animation: _moverGivenAmount,
            builder:
                (context, _) => _AmountDisplay(
                  text: _moverGivenAmount.displayText,
                  currency: sourceAccount?.nativeCurrency,
                ),
          ),
        ),
        const SizedBox(height: 8),
        Center(child: NumericKeypad(controller: _moverGivenAmount)),
        if (!differentCurrency)
          Builder(
            builder: (context) {
              final excess = _moverForeignExcess(
                sourceAccount,
                destinationAccount,
              );
              if (excess == null) return const SizedBox.shrink();
              final resultingBalance = _formatCentsAsAmount(
                ref
                        .read(ledgerProjectionsProvider)
                        .accountBalance(sourceAccount!.id)
                        .native
                        .amount -
                    _moverGivenAmount.amountMinorUnits,
              );
              return _MoverExcessAnnouncement(
                currency: sourceAccount.nativeCurrency,
                resultingBalance:
                    '$resultingBalance ${sourceAccount.nativeCurrency.value}',
                onRegisterRate: _openRecordRatesDialog,
              );
            },
          ),
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
                      sourceAccount,
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
                      sourceAccount,
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
                          '(${_foreignCurrencyOfPair(sourceAccount, destinationAccount).value}/USD)',
            ),
            onChanged: (_) => setState(() {}),
          ),
          Builder(
            builder: (context) {
              final derived = _deriveOtherFieldText(
                sourceAccount,
                destinationAccount,
              );
              if (derived == null) return const SizedBox.shrink();
              final label =
                  _rateInputMode == _RateInputMode.receivedAmount
                      ? 'Tasa: $derived '
                          '${_foreignCurrencyOfPair(sourceAccount, destinationAccount).value}/USD'
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

/// The typed amount next to the currency it's being entered in (#118) — the
/// same digits mean a different amount depending on the selected account's
/// currency, so the sheet must always show which one is in play.
class _AmountDisplay extends StatelessWidget {
  const _AmountDisplay({required this.text, required this.currency});

  final String text;
  final CurrencyCode? currency;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          text,
          key: const Key('amountDisplay'),
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        if (currency != null) ...[
          const SizedBox(width: 8),
          Text(
            currency!.value,
            key: const Key('amountCurrency'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ],
    );
  }
}

/// Shows how a foreign-currency Gasto/Ingreso will be valued (ADR-0018 §6):
/// today's parallel rate, a warning when the latest observation is stale, or
/// a blocking notice with a shortcut to register one when none exists at
/// all. Purely informational when a rate exists — it never blocks Save by
/// itself; [_QuickAddExpenseSheetState._rateBlocked] is what gates Save, and
/// only for the "no rate at all" case.
class _RateValuationAnnouncement extends ConsumerWidget {
  const _RateValuationAnnouncement({
    required this.currency,
    required this.onRegisterRate,
  });

  final CurrencyCode currency;
  final VoidCallback onRegisterRate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rateAsync = ref.watch(latestParaleloRateProvider(currency));
    return rateAsync.when(
      data: (resolution) => _build(context, resolution),
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _build(BuildContext context, Resolution? resolution) {
    if (resolution == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'No hay tasa registrada para ${currency.value}.',
                key: const Key('rateUnavailableMessage'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
            TextButton(
              key: const Key('registerRateShortcut'),
              onPressed: onRegisterRate,
              child: const Text('Registrar tasa'),
            ),
          ],
        ),
      );
    }

    final observedLocal = resolution.observedAt.toLocal();
    final rateText = resolution.nativePerUsd.toStringAsFixed(2);
    final sourceLabel = _sourceLabel(resolution.source);

    if (_isToday(observedLocal)) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Valorado a $rateText ${currency.value}/USD · $sourceLabel, '
          '${_recency(observedLocal, resolution.source)}',
          key: const Key('rateValuationAnnouncement'),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '⚠ Sin actualizar desde el ${_formatShortDate(observedLocal)} '
              '— valorando a $rateText',
              key: const Key('staleRateWarning'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
          TextButton(
            key: const Key('registerRateShortcut'),
            onPressed: onRegisterRate,
            child: const Text('Poner la tasa a mano'),
          ),
        ],
      ),
    );
  }
}

/// Announces how a same-currency non-USD Mover's excess will be valued
/// (ADR-0018 §3): only shown once the typed amount exceeds the source
/// Account's known balance, since the covered portion moves its frozen cost
/// proportionally and no rate ever participates in it — announcing one for
/// the covered case would be a lie.
class _MoverExcessAnnouncement extends ConsumerWidget {
  const _MoverExcessAnnouncement({
    required this.currency,
    required this.resultingBalance,
    required this.onRegisterRate,
  });

  final CurrencyCode currency;
  final String resultingBalance;
  final VoidCallback onRegisterRate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rateAsync = ref.watch(latestParaleloRateProvider(currency));
    return rateAsync.when(
      data: (resolution) => _build(context, resolution),
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _build(BuildContext context, Resolution? resolution) {
    if (resolution == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'El exceso necesita una tasa para ${currency.value} y no '
                'hay ninguna registrada.',
                key: const Key('moverExcessRateUnavailableMessage'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
            TextButton(
              key: const Key('moverRegisterRateShortcut'),
              onPressed: onRegisterRate,
              child: const Text('Registrar tasa'),
            ),
          ],
        ),
      );
    }

    final observedLocal = resolution.observedAt.toLocal();
    final rateText = resolution.nativePerUsd.toStringAsFixed(2);
    final sourceLabel = _sourceLabel(resolution.source);
    final dateSuffix =
        _isToday(observedLocal)
            ? _recency(observedLocal, resolution.source)
            : _formatShortDate(observedLocal);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        'El exceso se valora a $rateText ${currency.value}/USD · '
        '$sourceLabel, $dateSuffix — origen quedará en $resultingBalance',
        key: const Key('moverExcessValuationAnnouncement'),
      ),
    );
  }
}
