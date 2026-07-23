import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/domain/rate_observation.dart';

import '../../../../providers/composition_root.dart';
import '../../../../providers/tasas_providers.dart';
import '../../application/patrimonio_providers.dart';

/// First visible Patrimonio screen (#79): net worth at real cost only, no
/// rate overlay yet. Shows a guidance empty state when the catalog has no
/// accounts, rather than a spinner or a bare zero.
class PatrimonioScreen extends ConsumerWidget {
  const PatrimonioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogAsync = ref.watch(catalogRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Patrimonio'),
        actions: const [_RecordRatesAction()],
      ),
      body: catalogAsync.when(
        data: (catalog) {
          if (catalog.accounts.isEmpty) {
            return const _EmptyState();
          }
          return const _NetWorthHeader();
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('Error: $error')),
      ),
    );
  }
}

class _NetWorthHeader extends ConsumerWidget {
  const _NetWorthHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final netWorthAsync = ref.watch(netWorthUsdProvider);

    return Center(
      child: netWorthAsync.when(
        data: (usd) {
          final dollars = usd / 100;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Net worth (real cost)'),
              const SizedBox(height: 8),
              Text(
                '\$${dollars.toStringAsFixed(2)}',
                key: const Key('netWorthAmount'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ],
          );
        },
        loading: () => const CircularProgressIndicator(),
        error: (error, stackTrace) => Text('Error: $error'),
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
          'No accounts yet. Add an account to see your net worth here.',
          key: Key('patrimonioEmptyState'),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// Minimal manual capture action (ADR-0016 §4): appends one observation for
/// BCV and one for the parallel rate. Append-only — there is no
/// rate-management/history screen.
class _RecordRatesAction extends StatelessWidget {
  const _RecordRatesAction();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const Key('recordRatesAction'),
      icon: const Icon(Icons.currency_exchange),
      tooltip: 'Record rates',
      onPressed: () => showDialog<void>(
        context: context,
        builder: (context) => const _RecordRatesDialog(),
      ),
    );
  }
}

class _RecordRatesDialog extends ConsumerStatefulWidget {
  const _RecordRatesDialog();

  @override
  ConsumerState<_RecordRatesDialog> createState() =>
      _RecordRatesDialogState();
}

class _RecordRatesDialogState extends ConsumerState<_RecordRatesDialog> {
  final _bcvController = TextEditingController();
  final _paraleloController = TextEditingController();
  String? _error;
  bool _isSaving = false;

  @override
  void dispose() {
    _bcvController.dispose();
    _paraleloController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final bcvRate = Decimal.tryParse(_bcvController.text);
    final paraleloRate = Decimal.tryParse(_paraleloController.text);
    if (bcvRate == null || paraleloRate == null) {
      setState(() => _error = 'Enter both rates as a number.');
      return;
    }

    setState(() {
      _error = null;
      _isSaving = true;
    });

    try {
      final useCase = await ref.read(recordRateUseCaseProvider.future);
      final observedAt = DateTime.now().toUtc();
      final currency = CurrencyCode('VES');

      await useCase.execute(
        bcv: RateObservation(
          currency: currency,
          nativePerUsd: bcvRate,
          observedAt: observedAt,
          source: 'manual:bcv',
        ),
        paralelo: RateObservation(
          currency: currency,
          nativePerUsd: paraleloRate,
          observedAt: observedAt,
          source: 'manual:paralelo',
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
    return AlertDialog(
      title: const Text('Record today\'s rates'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('bcvRateField'),
            controller: _bcvController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'BCV (VES per USD)'),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('paraleloRateField'),
            controller: _paraleloController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Paralelo (VES per USD)',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          key: const Key('saveRatesButton'),
          onPressed: _isSaving ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
