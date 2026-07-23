import 'package:contabilidad/application/catalog/catalog_repository.dart';
import 'package:contabilidad/application/catalog/models/envelope.dart';
import 'package:contabilidad/domain/ports/ledger_projections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_kernel/shared_kernel.dart';

import '../providers/composition_root.dart';
import '../providers/ledger_providers.dart';

/// Envelope creation is out of scope for this slice (#74) — a movement can
/// only target one of the four system envelopes, which are the only ones
/// [CatalogRepository] can enumerate without a general `envelopeIds` port.
const _recordableEnvelopeRoles = [
  EnvelopeRole.stage,
  EnvelopeRole.differential,
  EnvelopeRole.adjustments,
  EnvelopeRole.opening,
];

class LedgerScreen extends ConsumerStatefulWidget {
  const LedgerScreen({super.key});

  @override
  ConsumerState<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends ConsumerState<LedgerScreen> {
  final _amountController = TextEditingController();
  EnvelopeRole _selectedRole = EnvelopeRole.stage;
  String? _error;
  bool _isRecording = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _record(CatalogRepository catalog) async {
    if (catalog.accountIds.isEmpty) {
      setState(() => _error = 'No account available.');
      return;
    }

    final amountValue = double.tryParse(_amountController.text);
    if (amountValue == null || amountValue <= 0) {
      setState(() => _error = 'Enter an amount greater than zero.');
      return;
    }

    setState(() {
      _error = null;
      _isRecording = true;
    });

    try {
      final recordIncome = await ref.read(recordIncomeProvider.future);
      final deviceId = await ref.read(deviceIdProvider.future);

      await recordIncome(
        eventId: EventId(DateTime.now().microsecondsSinceEpoch.toString()),
        deviceId: deviceId,
        accountId: catalog.accountIds.first,
        envelopeId: catalog.getSystemEnvelope(_selectedRole),
        amount: Money(
          amount: BigInt.from((amountValue * 100).round()),
          currency: CurrencyCode('USD'),
        ),
        source: 'Manual entry',
      );

      _amountController.clear();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isRecording = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(catalogRepositoryProvider);
    final projections = ref.watch(ledgerProjectionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Ledger')),
      body: catalogAsync.when(
        data: (catalog) => _buildBody(catalog, projections),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('Error: $error')),
      ),
    );
  }

  Widget _buildBody(CatalogRepository catalog, LedgerProjections projections) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            children: [
              for (final accountId in catalog.accountIds)
                _AccountTile(
                  name: catalog.getAccount(accountId)?.name ?? accountId.value,
                  balance: projections.accountBalance(accountId),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('amountField'),
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Amount (USD)'),
              ),
              const SizedBox(height: 8),
              DropdownButton<EnvelopeRole>(
                key: const Key('envelopeDropdown'),
                value: _selectedRole,
                items: [
                  for (final role in _recordableEnvelopeRoles)
                    DropdownMenuItem(
                      value: role,
                      child: Text(_envelopeLabel(catalog, role)),
                    ),
                ],
                onChanged: (role) {
                  if (role != null) setState(() => _selectedRole = role);
                },
              ),
              const SizedBox(height: 8),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ElevatedButton(
                key: const Key('recordButton'),
                onPressed: _isRecording ? null : () => _record(catalog),
                child: const Text('Record'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _envelopeLabel(CatalogRepository catalog, EnvelopeRole role) {
    final id = catalog.getSystemEnvelope(role);
    return catalog.getEnvelope(id)?.name ?? role.name;
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.name, required this.balance});

  final String name;
  final AccountBalance balance;

  @override
  Widget build(BuildContext context) {
    final native = balance.native.amount.toInt() / 100;
    final usd = balance.usd / 100;

    return ListTile(
      title: Text(name),
      subtitle: Text(
        '${balance.native.currency.value} ${native.toStringAsFixed(2)}',
      ),
      trailing: Text('\$${usd.toStringAsFixed(2)}'),
    );
  }
}
