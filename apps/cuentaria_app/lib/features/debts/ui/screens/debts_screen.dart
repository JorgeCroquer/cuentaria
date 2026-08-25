import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_kernel/shared_kernel.dart';

import '../../../../providers/composition_root.dart';
import '../../../accounts/application/account_providers.dart';
import '../../../accounts/ui/account_form_validators.dart';
import '../../../patrimonio/application/patrimonio_providers.dart';

const _debtCurrencies = ['USD', 'VES'];

/// Debts screen (S3, #205): lists Debt Accounts — Catalog Accounts tagged
/// with a counterparty person label (ADR-0022) — reachable from Patrimonio's
/// overflow menu. Balances arrive with the motor slice (patrimonio/ledger
/// projections); until then a row is just the person's name existing.
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
    final catalogAsync = ref.watch(catalogRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Deudas')),
      body: catalogAsync.when(
        data: (catalog) {
          final debtAccounts =
              catalog.accounts
                  .where((a) => !a.isArchived && a.isDebtAccount)
                  .toList();
          if (debtAccounts.isEmpty) {
            return _EmptyState(onCreate: _openCreateDialog);
          }
          return ListView(
            children: [
              for (final account in debtAccounts)
                ListTile(
                  key: Key('debtAccount_${account.id.value}'),
                  title: Text(account.counterpartyName!),
                ),
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
