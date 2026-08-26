import 'package:deudas/deudas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_kernel/shared_kernel.dart';

import '../../../../providers/composition_root.dart';
import '../../../accounts/application/account_providers.dart';
import '../../../accounts/ui/account_form_validators.dart';
import '../../../patrimonio/application/patrimonio_providers.dart';
import '../../../reconciliation/ui/screens/reconciliation_sheet.dart';
import '../../application/debts_providers.dart';

const _debtCurrencies = ['USD', 'VES'];

String _formatUsdCents(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';

bool _isFromToday(DateTime date) {
  final now = DateTime.now();
  return date.year == now.year &&
      date.month == now.month &&
      date.day == now.day;
}

const _monthAbbreviations = [
  'ene', 'feb', 'mar', 'abr', 'may', 'jun',
  'jul', 'ago', 'sep', 'oct', 'nov', 'dic', //
];

String _formatShortDate(DateTime date) =>
    '${date.day} ${_monthAbbreviations[date.month - 1]}';

/// Announces what a currency leg valued today with (ADR-0018 §4: never a
/// silent 1:1) — "tasa 50.00, hoy"/"tasa 50.00, 3 ago", or "sin tasa" when
/// no parallel observation exists.
String _rateAnnouncement(RateObservationView? rate) {
  if (rate == null) return 'sin tasa';
  final observedLocal = rate.observedAt.toLocal();
  final dateLabel =
      _isFromToday(observedLocal) ? 'hoy' : _formatShortDate(observedLocal);
  return 'tasa ${rate.nativePerUsd.toStringAsFixed(2)}, $dateLabel';
}

/// Debts screen (S3, #205/#207): lists Debt Accounts — Catalog Accounts
/// tagged with a counterparty person label (ADR-0022) — reachable from
/// Patrimonio's overflow menu. Balances come from [debtsSnapshotProvider]
/// (the deudas motor's own composition-root mapping, mirroring
/// patrimonioSnapshotProvider's pattern), with the sign spoken in the
/// user's language rather than a raw signed number.
class DebtsScreen extends ConsumerStatefulWidget {
  const DebtsScreen({super.key});

  @override
  ConsumerState<DebtsScreen> createState() => _DebtsScreenState();
}

class _DebtsScreenState extends ConsumerState<DebtsScreen> {
  Future<void> _openCreateDialog() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => const _PersonFormDialog(),
    );
    if (changed == true && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final snapshotAsync = ref.watch(debtsSnapshotProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Deudas')),
      body: snapshotAsync.when(
        data: (snapshot) {
          if (snapshot.personas.isEmpty) {
            return _EmptyState(onCreate: _openCreateDialog);
          }
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _formatUsdCents(snapshot.globalNetoUsdCents),
                  key: const Key('debtsGlobalAmount'),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              for (final persona in snapshot.personas)
                _PersonTile(persona: persona),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('Error: $error')),
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('addPersonFab'),
        onPressed: _openCreateDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// One counterparty's row: sign spoken in the user's language ("Pedro te
/// debe $200.00" / "le debés $12.00 a Ana") plus one detail line per
/// currency leg — always visible so a two-currency person shows both, and a
/// non-USD leg announces the rate it valued at (or "sin tasa").
class _PersonTile extends StatelessWidget {
  const _PersonTile({required this.persona});

  final PersonDebts persona;

  @override
  Widget build(BuildContext context) {
    final headline =
        persona.netoUsdCents >= 0
            ? '${persona.personName} te debe '
                '${_formatUsdCents(persona.netoUsdCents)}'
            : 'le debés ${_formatUsdCents(-persona.netoUsdCents)} a '
                '${persona.personName}';

    return ListTile(
      key: Key('debtPerson_${persona.personName}'),
      title: Text(headline),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final leg in persona.currencies)
            _CurrencyLegLine(leg: leg, personName: persona.personName),
        ],
      ),
    );
  }
}

/// One currency leg's line, with the two actions that close the Debt
/// Account lifecycle (#209, ADR-0022 §4): **Conciliar** launches the
/// existing C3 Reconciliation ritual preselecting this Debt Account — the
/// same ritual a liquid Cuenta uses, since the Splitwise import is that
/// ritual, not a bespoke flow. **Archivar** only appears once this leg's
/// native balance is exactly zero, and always asks before archiving.
class _CurrencyLegLine extends ConsumerWidget {
  const _CurrencyLegLine({required this.leg, required this.personName});

  final PersonCurrencyDebt leg;
  final String personName;

  static final _usd = CurrencyCode('USD');

  Future<void> _reconcile(BuildContext context, WidgetRef ref) async {
    final catalog = await ref.read(catalogRepositoryProvider.future);
    final account = catalog.getAccount(leg.accountId);
    if (account == null || !context.mounted) return;
    await showReconciliationSheet(context, account);
    ref.invalidate(debtsSnapshotProvider);
    ref.invalidate(patrimonioSnapshotProvider);
  }

  Future<void> _archive(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Archivar deuda'),
            content: Text(
              '¿Archivar la cuenta de $personName en '
              '${leg.currency.value}? Ya está en \$0,00.',
            ),
            actions: [
              TextButton(
                key: const Key('archiveDebtCancelButton'),
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                key: const Key('archiveDebtConfirmButton'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Archivar'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;

    final archiveAccount = await ref.read(archiveAccountProvider.future);
    await archiveAccount(leg.accountId);
    ref.invalidate(debtsSnapshotProvider);
    ref.invalidate(patrimonioSnapshotProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final valueText =
        '${leg.currency.value}: ${_formatUsdCents(leg.todayValueUsdCents)}';
    final isZero = leg.nativeMinorAmount == BigInt.zero;

    return Row(
      children: [
        Expanded(
          child:
              leg.currency == _usd
                  ? Text(valueText)
                  : Text('$valueText · ${_rateAnnouncement(leg.parallelRate)}'),
        ),
        IconButton(
          key: Key('reconcileDebtAccount_${leg.accountId.value}'),
          icon: const Icon(Icons.sync_alt),
          tooltip: 'Conciliar',
          onPressed: () => _reconcile(context, ref),
        ),
        if (isZero)
          IconButton(
            key: Key('archiveDebtAccount_${leg.accountId.value}'),
            icon: const Icon(Icons.archive_outlined),
            tooltip: 'Archivar',
            onPressed: () => _archive(context, ref),
          ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Todavía no hay personas',
              key: Key('debtsEmptyState'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              key: const Key('createPersonCta'),
              onPressed: onCreate,
              child: const Text('Crear persona'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonFormDialog extends ConsumerStatefulWidget {
  const _PersonFormDialog();

  @override
  ConsumerState<_PersonFormDialog> createState() => _PersonFormDialogState();
}

class _PersonFormDialogState extends ConsumerState<_PersonFormDialog> {
  late final TextEditingController _nameController;
  String _currency = _debtCurrencies.first;
  String? _error;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final nameError = validateAccountName(_nameController.text);
    if (nameError != null) {
      setState(() => _error = nameError);
      return;
    }

    setState(() {
      _error = null;
      _isSaving = true;
    });

    try {
      final createAccount = await ref.read(createAccountProvider.future);
      final deviceId = await ref.read(deviceIdProvider.future);
      final name = _nameController.text.trim();

      await createAccount(
        name: name,
        nativeCurrency: CurrencyCode(_currency),
        counterpartyName: name,
        eventId: EventId(DateTime.now().microsecondsSinceEpoch.toString()),
        deviceId: deviceId,
      );

      ref.invalidate(patrimonioSnapshotProvider);
      ref.invalidate(debtsSnapshotProvider);
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
      title: const Text('Nueva persona'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('personNameField'),
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            const SizedBox(height: 8),
            DropdownButton<String>(
              key: const Key('personCurrencyDropdown'),
              value: _currency,
              items: [
                for (final code in _debtCurrencies)
                  DropdownMenuItem(value: code, child: Text(code)),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _currency = value);
              },
            ),
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
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          key: const Key('savePersonButton'),
          onPressed: _isSaving ? null : _save,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
