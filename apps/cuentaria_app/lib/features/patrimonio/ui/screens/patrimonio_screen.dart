import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../providers/composition_root.dart';
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
      appBar: AppBar(title: const Text('Patrimonio')),
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
