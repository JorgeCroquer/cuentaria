import 'package:contabilidad/application/catalog/models/account.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/application/rate_resolution_service.dart';
import 'package:tasas/domain/rate_resolver.dart';

import '../../../../providers/composition_root.dart';
import '../../../../providers/tasas_providers.dart';
import '../../../../ui/theme/app_theme.dart';
import '../../../patrimonio/application/patrimonio_providers.dart';
import '../../../reconciliation/ui/screens/reconciliation_sheet.dart';
import '../../application/account_providers.dart';
import '../account_form_validators.dart';

const _availableCurrencies = ['USD', 'VES', 'EUR'];

/// Human-readable provenance for a resolved Rate (#165/#166), matching the
/// announcement copy already used at capture time (ADR-0018 "la app
/// siempre anuncia con qué valoró").
String _sourceLabel(String source) => switch (source) {
  'binancep2p:ask' => 'Binance P2P',
  'dolarapi:paralelo' => 'DolarApi',
  _ => 'manual',
};

String _formatDate(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

String _colorToHex(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

Color? _hexToColor(String? hex) {
  if (hex == null) return null;
  final parsed = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
  if (parsed == null) return null;
  return Color(0xFF000000 | parsed);
}

String _formatBalance(Money balance) {
  final decimal =
      (Decimal.fromBigInt(balance.amount) / Decimal.fromInt(100)).toDecimal();
  return '${decimal.toStringAsFixed(2)} ${balance.currency.value}';
}

/// "Hace cuánto se concilió" (C3 slice 4, #150): the only reconciliation
/// reminder — never a blank when it was never reconciled.
String _formatLastReconciled(DateTime? lastReconciledAt) {
  if (lastReconciledAt == null) return 'Nunca conciliada';

  final elapsed = DateTime.now().difference(lastReconciledAt);
  if (elapsed.inDays >= 365) {
    final years = elapsed.inDays ~/ 365;
    return 'Conciliada hace $years ${years == 1 ? 'año' : 'años'}';
  }
  if (elapsed.inDays >= 30) {
    final months = elapsed.inDays ~/ 30;
    return 'Conciliada hace $months ${months == 1 ? 'mes' : 'meses'}';
  }
  if (elapsed.inDays >= 1) {
    return 'Conciliada hace ${elapsed.inDays} ${elapsed.inDays == 1 ? 'día' : 'días'}';
  }
  if (elapsed.inHours >= 1) {
    return 'Conciliada hace ${elapsed.inHours} ${elapsed.inHours == 1 ? 'hora' : 'horas'}';
  }
  if (elapsed.inMinutes >= 1) {
    return 'Conciliada hace ${elapsed.inMinutes} '
        '${elapsed.inMinutes == 1 ? 'minuto' : 'minutos'}';
  }
  return 'Conciliada hace instantes';
}

/// Accounts catalog (#94): create, edit and archive Accounts, reachable
/// from Patrimonio. Editing/archiving mutate the same [CatalogRepository]
/// instance Patrimonio reads, so this screen rebuilds itself locally after
/// each mutation and invalidates [patrimonioSnapshotProvider] so Patrimonio
/// picks up the change reactively without a domain event on the bus (catalog
/// mutations don't publish to the EventBus — only ledger transactions do).
class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  Future<void> _openCreateDialog() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => const _AccountFormDialog(),
    );
    if (changed == true && mounted) setState(() {});
  }

  Future<void> _openEditDialog(Account account) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => _AccountFormDialog(existing: account),
    );
    if (changed == true && mounted) setState(() {});
  }

  Future<void> _archive(Account account) async {
    final archiveAccount = await ref.read(archiveAccountProvider.future);
    await archiveAccount(account.id);
    ref.invalidate(patrimonioSnapshotProvider);
    if (mounted) setState(() {});
  }

  /// Reconciliation reachable from a Cuenta's row (C3 slice 1, #147): this
  /// slice deliberately owns the only entry point — slices 2-4 hang off the
  /// sheet this opens and never touch navigation again (U1's four sibling
  /// slices stepped on each other by each adding their own route).
  Future<void> _openReconciliationSheet(Account account) async {
    await showReconciliationSheet(context, account);
    ref.invalidate(patrimonioSnapshotProvider);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(catalogRepositoryProvider);
    final projections = ref.watch(ledgerProjectionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Cuentas')),
      body: catalogAsync.when(
        data: (catalog) {
          final accounts =
              catalog.accounts.where((a) => !a.isArchived).toList();
          if (accounts.isEmpty) {
            return const _EmptyState();
          }
          return ListView(
            children: [
              for (final account in accounts)
                _AccountTile(
                  account: account,
                  balance: projections.accountBalance(account.id).native,
                  onReconcile: () => _openReconciliationSheet(account),
                  onEdit: () => _openEditDialog(account),
                  onArchive: () => _archive(account),
                ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('Error: $error')),
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('addAccountFab'),
        onPressed: _openCreateDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.account,
    required this.balance,
    required this.onReconcile,
    required this.onEdit,
    required this.onArchive,
  });

  final Account account;
  final Money balance;
  final VoidCallback onReconcile;
  final VoidCallback onEdit;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final color =
        _hexToColor(account.colorHex) ?? Theme.of(context).colorScheme.primary;
    final isNegative = balance.amount < BigInt.zero;
    return ListTile(
      key: Key('account_${account.id.value}'),
      onTap: onReconcile,
      leading: CircleAvatar(backgroundColor: color, radius: 12),
      title: Text(account.name),
      subtitle: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(account.nativeCurrency.value),
          Text(
            _formatLastReconciled(account.lastReconciledAt),
            key: Key('lastReconciled_${account.id.value}'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isNegative)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Tooltip(
                message: 'Saldo negativo — ¿falta registrar un ingreso?',
                child: Icon(
                  Icons.error_outline,
                  key: Key('negativeBalanceIndicator_${account.id.value}'),
                  color: Theme.of(context).colorScheme.error,
                  size: 18,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              _formatBalance(balance),
              key: Key('accountBalance_${account.id.value}'),
              style:
                  isNegative
                      ? TextStyle(color: Theme.of(context).colorScheme.error)
                      : null,
            ),
          ),
          IconButton(
            key: Key('editAccount_${account.id.value}'),
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: onEdit,
          ),
          IconButton(
            key: Key('archiveAccount_${account.id.value}'),
            icon: const Icon(Icons.archive_outlined),
            tooltip: 'Archive',
            onPressed: onArchive,
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'No accounts yet. Tap + to create one.',
          key: Key('accountsEmptyState'),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _AccountFormDialog extends ConsumerStatefulWidget {
  const _AccountFormDialog({this.existing});

  final Account? existing;

  bool get isEdit => existing != null;

  @override
  ConsumerState<_AccountFormDialog> createState() => _AccountFormDialogState();
}

class _AccountFormDialogState extends ConsumerState<_AccountFormDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _openingBalanceController;
  late final TextEditingController _openingBalanceRateController;
  late String _currency;
  String? _colorHex;
  String? _error;
  bool _isSaving = false;
  Resolution? _suggestedRate;
  bool _rateOverridden = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _openingBalanceController = TextEditingController();
    _openingBalanceRateController = TextEditingController();
    _currency = existing?.nativeCurrency.value ?? _availableCurrencies.first;
    _colorHex = existing?.colorHex;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _openingBalanceController.dispose();
    _openingBalanceRateController.dispose();
    super.dispose();
  }

  /// A non-USD account always needs a rate — with an opening balance it
  /// freezes the real cost of the opening fact; without one, it's the first
  /// parallel-rate observation the app needs (#112), asked for once instead
  /// of surfacing as a later error. Matches [validateOpeningBalanceRate].
  bool get _needsOpeningBalanceRate {
    if (widget.isEdit) return false;
    return _currency != 'USD';
  }

  /// Proposes the currency's already-known parallel rate (#166) so a fresh
  /// VES/etc. account doesn't ask the user for a number the app already
  /// has — the same Rate Resolution Chain [latestParaleloRateProvider]
  /// wraps for the capture sheet's valuation hint, called directly here
  /// rather than through that provider: it isn't autoDispose, so reading it
  /// this early (before the account/rate even exist) would cache a stale
  /// `null` that nothing besides that provider's own writers would know to
  /// invalidate. A currency with no automatic source (e.g. EUR) resolves to
  /// `null` and the field stays empty, unchanged from today's behavior.
  Future<void> _loadSuggestedRate() async {
    final currency = CurrencyCode(_currency);
    final series = await ref.read(rateSeriesProvider.future);
    final resolution = await RateResolutionService(series)(currency);
    if (!mounted || _currency != currency.value) return;
    setState(() {
      _suggestedRate = resolution;
      if (resolution != null && !_rateOverridden) {
        _openingBalanceRateController.text = resolution.nativePerUsd.toString();
      }
    });
  }

  Future<void> _save() async {
    final nameError = validateAccountName(_nameController.text);
    if (nameError != null) {
      setState(() => _error = nameError);
      return;
    }
    final balanceError =
        widget.isEdit
            ? null
            : validateOpeningBalance(_openingBalanceController.text);
    if (balanceError != null) {
      setState(() => _error = balanceError);
      return;
    }
    final rateError =
        widget.isEdit
            ? null
            : validateOpeningBalanceRate(
              currency: _currency,
              rateText: _openingBalanceRateController.text,
            );
    if (rateError != null) {
      setState(() => _error = rateError);
      return;
    }

    setState(() {
      _error = null;
      _isSaving = true;
    });

    try {
      if (widget.isEdit) {
        final updateAccount = await ref.read(updateAccountProvider.future);
        await updateAccount(
          id: widget.existing!.id,
          name: _nameController.text.trim(),
          colorHex: _colorHex,
        );
      } else {
        final createAccount = await ref.read(createAccountProvider.future);
        final deviceId = await ref.read(deviceIdProvider.future);
        final openingWholeUnits = int.tryParse(
          _openingBalanceController.text.trim(),
        );
        final currency = CurrencyCode(_currency);
        final trimmedRate = _openingBalanceRateController.text.trim();

        await createAccount(
          name: _nameController.text.trim(),
          nativeCurrency: currency,
          colorHex: _colorHex,
          openingBalance:
              (openingWholeUnits != null && openingWholeUnits > 0)
                  ? Money(
                    amount: BigInt.from(openingWholeUnits * 100),
                    currency: currency,
                  )
                  : null,
          openingBalanceRate:
              trimmedRate.isEmpty ? null : Decimal.parse(trimmedRate),
          suggestedRate: _suggestedRate?.nativePerUsd,
          eventId: EventId(DateTime.now().microsecondsSinceEpoch.toString()),
          deviceId: deviceId,
        );
      }

      ref.invalidate(patrimonioSnapshotProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isEdit ? 'Edit account' : 'New account'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('accountNameField'),
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 8),
            if (widget.isEdit)
              Text('Currency: ${widget.existing!.nativeCurrency.value}')
            else
              DropdownButton<String>(
                key: const Key('accountCurrencyDropdown'),
                value: _currency,
                items: [
                  for (final code in _availableCurrencies)
                    DropdownMenuItem(value: code, child: Text(code)),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _currency = value;
                    _suggestedRate = null;
                    _rateOverridden = false;
                    _openingBalanceRateController.clear();
                  });
                  if (value != 'USD') _loadSuggestedRate();
                },
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final color in AppColors.palette)
                  GestureDetector(
                    key: Key('colorSwatch_${_colorToHex(color)}'),
                    onTap: () => setState(() => _colorHex = _colorToHex(color)),
                    child: CircleAvatar(
                      backgroundColor: color,
                      radius: 14,
                      child:
                          _colorHex == _colorToHex(color)
                              ? const Icon(
                                Icons.check,
                                size: 16,
                                color: Colors.white,
                              )
                              : null,
                    ),
                  ),
              ],
            ),
            if (!widget.isEdit) ...[
              const SizedBox(height: 8),
              TextField(
                key: const Key('openingBalanceField'),
                controller: _openingBalanceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Opening balance (optional, whole units)',
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (_needsOpeningBalanceRate) ...[
                const SizedBox(height: 8),
                TextField(
                  key: const Key('openingBalanceRateField'),
                  controller: _openingBalanceRateController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Exchange rate ($_currency per USD)',
                  ),
                  onChanged: (_) => setState(() => _rateOverridden = true),
                ),
                if (_suggestedRate != null && !_rateOverridden)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${_suggestedRate!.nativePerUsd.toStringAsFixed(2)} '
                      '(${_sourceLabel(_suggestedRate!.source)}, '
                      '${_formatDate(_suggestedRate!.observedAt.toLocal())})',
                      key: const Key('suggestedRateAnnouncement'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          key: const Key('saveAccountButton'),
          onPressed: _isSaving ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
