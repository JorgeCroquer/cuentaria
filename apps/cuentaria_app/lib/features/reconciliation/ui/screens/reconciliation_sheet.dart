import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:contabilidad/domain/account_balance.dart';
import 'package:contabilidad/domain/reconciliation/reconciliation_planner.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_kernel/shared_kernel.dart';

import '../../../../providers/composition_root.dart';
import '../../../../providers/tasas_providers.dart';
import '../../../capture/application/capture_providers.dart';
import '../../../capture/ui/amount_input_controller.dart';
import '../../../capture/ui/widgets/numeric_keypad.dart';
import '../../../envelopes/application/envelopes_providers.dart';
import '../../../patrimonio/ui/screens/patrimonio_screen.dart';
import '../../application/reconciliation_providers.dart';

/// Opens the Reconciliation sheet (C3 slice 1, #147, ADR-0019) for
/// [account], reachable by tapping its row in Cuentas.
Future<void> showReconciliationSheet(BuildContext context, Account account) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => ReconciliationSheet(account: account),
  );
}

String _formatMoney(Money money) {
  final decimal =
      (Decimal.fromBigInt(money.amount) / Decimal.fromInt(100)).toDecimal();
  return '${decimal.toStringAsFixed(2)} ${money.currency.value}';
}

String _formatNative(BigInt minorUnits, CurrencyCode currency) =>
    _formatMoney(Money(amount: minorUnits, currency: currency));

String _formatUsdCents(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';

/// Asks for a Cuenta's real native-currency balance, shows the resulting
/// delta against the projected one, and posts it (ADR-0019): `Absorb` and
/// `NothingToReconcile` post directly; a routed delta offers to register the
/// Income/Expense it implies via the existing quick-add capture use cases
/// (ADR-0019 §2), reusing their factories rather than duplicating them, or
/// the user can still take the "absorb anyway" escape hatch (ADR-0019 §1).
class ReconciliationSheet extends ConsumerStatefulWidget {
  const ReconciliationSheet({required this.account, super.key});

  final Account account;

  @override
  ConsumerState<ReconciliationSheet> createState() =>
      _ReconciliationSheetState();
}

class _ReconciliationSheetState extends ConsumerState<ReconciliationSheet> {
  final _realBalance = AmountInputController();

  // AmountInputController.isValid requires a strictly positive amount — the
  // right rule for capture, where $0 means nothing was typed. In
  // Reconciliation a declared real balance of exactly zero is legitimate
  // (an emptied wallet), so the sheet tracks "have any digits been typed at
  // all" itself instead of reusing that getter.
  bool _hasTypedDigits = false;
  bool _isSaving = false;
  String? _error;

  // RouteToIncome
  final _incomeSourceController = TextEditingController();

  // RouteToExpense
  EnvelopeId? _selectedExpenseEnvelopeId;

  @override
  void initState() {
    super.initState();
    _realBalance.addListener(_onRealBalanceChanged);
    _incomeSourceController.addListener(_onIncomeSourceChanged);
  }

  void _onRealBalanceChanged() {
    if (!mounted) return;
    setState(() => _hasTypedDigits = true);
  }

  void _onIncomeSourceChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _realBalance.removeListener(_onRealBalanceChanged);
    _realBalance.dispose();
    _incomeSourceController.removeListener(_onIncomeSourceChanged);
    _incomeSourceController.dispose();
    super.dispose();
  }

  void _openRecordRatesDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => const RecordRatesDialog(),
    );
  }

  ReconciliationOutcome? _previewOutcome(Money projectedNative, Decimal rate) {
    if (!_hasTypedDigits) return null;
    final deltaNative = _realBalance.amountMinorUnits - projectedNative.amount;
    return planReconciliation(deltaNative: deltaNative, rate: rate);
  }

  Future<void> _confirm({required bool forceAbsorb}) async {
    setState(() {
      _error = null;
      _isSaving = true;
    });

    try {
      final useCase = await ref.read(reconcileUseCaseProvider.future);
      final deviceId = await ref.read(deviceIdProvider.future);

      await useCase(
        eventId: EventId(DateTime.now().microsecondsSinceEpoch.toString()),
        deviceId: deviceId,
        accountId: widget.account.id,
        realNativeBalance: Money(
          amount: _realBalance.amountMinorUnits,
          currency: widget.account.nativeCurrency,
        ),
        forceAbsorb: forceAbsorb,
      );

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Registers the routed surplus as an Income via [QuickAddIncomeUseCase]
  /// (ADR-0019 §2) — no envelope is passed, so it lands in Stage same as any
  /// manually captured Income.
  Future<void> _confirmRouteToIncome(RouteToIncome outcome) async {
    setState(() {
      _error = null;
      _isSaving = true;
    });

    try {
      final useCase = await ref.read(quickAddIncomeUseCaseProvider.future);
      final deviceId = await ref.read(deviceIdProvider.future);

      await useCase(
        eventId: EventId(DateTime.now().microsecondsSinceEpoch.toString()),
        deviceId: deviceId,
        accountId: widget.account.id,
        amount: Money(
          amount: outcome.deltaNative,
          currency: widget.account.nativeCurrency,
        ),
        source: _incomeSourceController.text.trim(),
      );

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Registers the routed shortage as an Expense via
  /// [QuickAddExpenseUseCase] (ADR-0019 §2), discounting the envelope the
  /// user picked.
  Future<void> _confirmRouteToExpense(RouteToExpense outcome) async {
    final envelopeId = _selectedExpenseEnvelopeId;
    if (envelopeId == null) return;

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
        accountId: widget.account.id,
        envelopeId: envelopeId,
        amount: Money(
          amount: -outcome.deltaNative,
          currency: widget.account.nativeCurrency,
        ),
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
    final projections = ref.watch(ledgerProjectionsProvider);
    final projectedBalance = projections.accountBalance(widget.account.id);
    final isUsd = widget.account.nativeCurrency == CurrencyCode('USD');

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child:
            isUsd
                ? _buildBody(projectedBalance, Decimal.one)
                : _buildForeignBody(projectedBalance),
      ),
    );
  }

  Widget _buildForeignBody(AccountBalance projectedBalance) {
    final rateAsync = ref.watch(
      latestParaleloRateProvider(widget.account.nativeCurrency),
    );
    return rateAsync.when(
      data: (observation) {
        if (observation == null) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'No hay tasa registrada para '
                    '${widget.account.nativeCurrency.value}.',
                    key: const Key('rateUnavailableMessage'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                TextButton(
                  key: const Key('registerRateShortcut'),
                  onPressed: _openRecordRatesDialog,
                  child: const Text('Registrar tasa'),
                ),
              ],
            ),
          );
        }
        return _buildBody(projectedBalance, observation.nativePerUsd);
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
    );
  }

  Widget _buildBody(AccountBalance projectedBalance, Decimal rate) {
    final outcome = _previewOutcome(projectedBalance.native, rate);
    final isRouted = outcome is RouteToIncome || outcome is RouteToExpense;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.account.name,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Proyectado: ${_formatMoney(projectedBalance.native)}',
            key: const Key('projectedBalanceText'),
          ),
          const SizedBox(height: 16),
          Center(
            child: AnimatedBuilder(
              animation: _realBalance,
              builder:
                  (context, _) => Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        _realBalance.displayText,
                        key: const Key('realBalanceDisplay'),
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.account.nativeCurrency.value,
                        key: const Key('realBalanceCurrency'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
            ),
          ),
          const SizedBox(height: 8),
          Center(child: NumericKeypad(controller: _realBalance)),
          const SizedBox(height: 16),
          if (outcome != null)
            _OutcomeMessage(
              outcome: outcome,
              currency: widget.account.nativeCurrency,
            ),
          if (outcome is RouteToIncome)
            _RouteToIncomeSection(
              isSaving: _isSaving,
              sourceController: _incomeSourceController,
              onConfirm: () => _confirmRouteToIncome(outcome),
            ),
          if (outcome is RouteToExpense)
            _RouteToExpenseSection(
              isSaving: _isSaving,
              selectedEnvelopeId: _selectedExpenseEnvelopeId,
              onEnvelopeSelected:
                  (id) => setState(() => _selectedExpenseEnvelopeId = id),
              onConfirm: () => _confirmRouteToExpense(outcome),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  key: const Key('reconciliationCancelButton'),
                  onPressed:
                      _isSaving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  key: const Key('reconciliationConfirmButton'),
                  onPressed:
                      !_hasTypedDigits || _isSaving || isRouted
                          ? null
                          : () => _confirm(forceAbsorb: false),
                  child: const Text('Confirmar'),
                ),
              ),
            ],
          ),
          if (isRouted) ...[
            const SizedBox(height: 8),
            TextButton(
              key: const Key('reconciliationAbsorbAnywayButton'),
              onPressed: _isSaving ? null : () => _confirm(forceAbsorb: true),
              child: const Text('Absorber de todos modos'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Describes the previewed [outcome] in Spanish before the user confirms —
/// the "absorbed against what" and "this is large" copy the acceptance
/// criteria require.
class _OutcomeMessage extends StatelessWidget {
  const _OutcomeMessage({required this.outcome, required this.currency});

  final ReconciliationOutcome outcome;
  final CurrencyCode currency;

  @override
  Widget build(BuildContext context) {
    return switch (outcome) {
      NothingToReconcile() => const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Text(
          'Saldo real igual al proyectado. No se registrará nada.',
          key: Key('reconciliationNothingMessage'),
        ),
      ),
      Absorb(:final deltaNative, :final deltaUsd) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          'Diferencia: ${_formatNative(deltaNative, currency)} '
          '(${_formatUsdCents(deltaUsd)}). Se absorbe contra Ajustes.',
          key: const Key('reconciliationAbsorbMessage'),
        ),
      ),
      RouteToIncome(:final deltaNative, :final suggestedUsd) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          'Diferencia grande: ${_formatNative(deltaNative, currency)} '
          '(${_formatUsdCents(suggestedUsd)}). Parece un cobro sin '
          'registrar — regístralo como Ingreso, o absorbe de todos modos.',
          key: const Key('reconciliationRouteWarning'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
      RouteToExpense(:final deltaNative, :final suggestedUsd) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          'Diferencia grande: ${_formatNative(deltaNative, currency)} '
          '(${_formatUsdCents(suggestedUsd)}). Parece un gasto sin '
          'registrar — regístralo como Gasto, o absorbe de todos modos.',
          key: const Key('reconciliationRouteWarning'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    };
  }
}

/// The routed Income capture (ADR-0019 §2): the amount is fixed to the
/// delta, so only the source of the money is asked before posting via
/// [QuickAddIncomeUseCase].
class _RouteToIncomeSection extends StatelessWidget {
  const _RouteToIncomeSection({
    required this.isSaving,
    required this.sourceController,
    required this.onConfirm,
  });

  final bool isSaving;
  final TextEditingController sourceController;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('routeToIncomeSourceField'),
            controller: sourceController,
            decoration: const InputDecoration(labelText: '¿De dónde vino?'),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            key: const Key('routeToIncomeConfirmButton'),
            onPressed:
                isSaving || sourceController.text.trim().isEmpty
                    ? null
                    : onConfirm,
            child: const Text('Registrar Ingreso'),
          ),
        ],
      ),
    );
  }
}

/// The routed Expense capture (ADR-0019 §2): the amount is fixed to the
/// delta, so only the Sobre it came out of is asked before posting via
/// [QuickAddExpenseUseCase].
class _RouteToExpenseSection extends ConsumerWidget {
  const _RouteToExpenseSection({
    required this.isSaving,
    required this.selectedEnvelopeId,
    required this.onEnvelopeSelected,
    required this.onConfirm,
  });

  final bool isSaving;
  final EnvelopeId? selectedEnvelopeId;
  final ValueChanged<EnvelopeId> onEnvelopeSelected;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final envelopesAsync = ref.watch(userEnvelopesProvider);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          envelopesAsync.when(
            data:
                (envelopes) =>
                    envelopes.isEmpty
                        ? const Text('No hay Sobres.')
                        : Wrap(
                          spacing: 8,
                          children: [
                            for (final envelope in envelopes)
                              ChoiceChip(
                                key: Key(
                                  'routeToExpenseEnvelopeChip_'
                                  '${envelope.id.value}',
                                ),
                                label: Text(envelope.name),
                                selected: envelope.id == selectedEnvelopeId,
                                onSelected:
                                    (_) => onEnvelopeSelected(envelope.id),
                              ),
                          ],
                        ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            key: const Key('routeToExpenseConfirmButton'),
            onPressed:
                isSaving || selectedEnvelopeId == null ? null : onConfirm,
            child: const Text('Registrar Gasto'),
          ),
        ],
      ),
    );
  }
}
