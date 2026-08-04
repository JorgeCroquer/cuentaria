import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:patrimonio/patrimonio.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/domain/rate_observation.dart';

import '../../../../providers/tasas_providers.dart';
import '../../../../ui/theme/app_icons.dart';
import '../../../../ui/theme/app_theme.dart';
import '../../application/patrimonio_providers.dart';

String _formatUsdCents(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';

String _formatNativeAmount(BigInt minorAmount, CurrencyCode currency) {
  final decimal =
      (Decimal.fromBigInt(minorAmount) / Decimal.fromInt(100)).toDecimal();
  return '${decimal.toStringAsFixed(2)} ${currency.value}';
}

/// The icon/color a user Envelope was tagged with in the management screen
/// (#95) — `null` (no leading widget) when neither was chosen, since older
/// Envelopes and system ones never carry appearance.
Widget? _envelopeLeading(PatrimonioEnvelope envelope) {
  if (envelope.iconId == null && envelope.colorIndex == null) return null;
  final color =
      envelope.colorIndex == null
          ? null
          : AppColors.palette[envelope.colorIndex! % AppColors.palette.length];
  return Icon(
    AppIcons.iconFor(envelope.iconId),
    color: color,
    key: Key('envelopeIcon_${envelope.id.value}'),
  );
}

/// Patrimonio screen (#82): header (real cost, today's value, unrealized
/// P&L, BCV reference) + accounts grouped by currency, driven end-to-end by
/// [patrimonioSnapshotProvider] — the engine, not the widget tree, does the
/// valuation math. Shows a guidance empty state when the catalog has no
/// accounts, rather than a spinner or a bare zero.
///
/// The empty-state check reads [patrimonioSnapshotProvider] rather than
/// [catalogRepositoryProvider] directly: the latter resolves once to a
/// mutable repository instance and never re-emits when an Account is added
/// to it, so a check against it would freeze on the empty state forever
/// after the first build. The snapshot provider already re-subscribes to
/// ledger Transactions and is explicitly invalidated by the Accounts screen
/// (#94) on every catalog mutation, so it reflects new Accounts reactively.
class PatrimonioScreen extends ConsumerWidget {
  const PatrimonioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(patrimonioSnapshotProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Patrimonio'),
        actions: const [
          _ManageAccountsAction(),
          _ManageEnvelopesAction(),
          _EditCascadeAction(),
          _RecordRatesAction(),
        ],
      ),
      body: snapshotAsync.when(
        data: (snapshot) {
          if (snapshot.accountGroups.isEmpty) {
            return const _EmptyState();
          }
          return const _PatrimonioBody();
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('Error: $error')),
      ),
    );
  }
}

class _PatrimonioBody extends ConsumerWidget {
  const _PatrimonioBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(patrimonioSnapshotProvider);

    return snapshotAsync.when(
      data:
          (snapshot) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Header(snapshot: snapshot),
              const SizedBox(height: 24),
              for (final envelope in snapshot.envelopes)
                _EnvelopeTile(envelope: envelope),
              const SizedBox(height: 24),
              for (final group in snapshot.accountGroups)
                _AccountGroupTile(group: group),
            ],
          ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => Center(child: Text('Error: $error')),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.snapshot});

  final PatrimonioSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Real cost'),
        Text(
          _formatUsdCents(snapshot.realCostUsdCents),
          key: const Key('realCostAmount'),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 16),
        const Text("Today's value (parallel)"),
        Text(
          _formatUsdCents(snapshot.todayValueUsdCents),
          key: const Key('todayValueAmount'),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Unrealized P&L: ${_formatUsdCents(snapshot.unrealizedPnlUsdCents)}',
          key: const Key('unrealizedPnlAmount'),
        ),
        const SizedBox(height: 8),
        Text(
          'BCV reference: ${_formatUsdCents(snapshot.bcvReferenceUsdCents)}',
          key: const Key('bcvReferenceAmount'),
        ),
        if (snapshot.hasMissingRate)
          const Text(
            'sin tasa — some currencies have no rate yet',
            key: Key('missingRateFlag'),
          ),
      ],
    );
  }
}

/// One entry in the Envelopes block ("para qué", #83): a user Envelope
/// rendered per its target metadata, or a system Envelope special-cased —
/// Stage as "Sin asignar" with direct access to the distribute flow (C2),
/// Apertura as a pending-distribution notice. Diferencial/Ajustes never
/// reach here — the engine excludes them (ADR-0015).
class _EnvelopeTile extends StatelessWidget {
  const _EnvelopeTile({required this.envelope});

  final PatrimonioEnvelope envelope;

  @override
  Widget build(BuildContext context) {
    final key = Key('envelope_${envelope.id.value}');

    if (envelope.role == EnvelopeRoleView.stage) {
      return ListTile(
        key: key,
        title: Text('Sin asignar: ${_formatUsdCents(envelope.balanceUsd)}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/distribute'),
      );
    }

    if (envelope.role == EnvelopeRoleView.opening) {
      return ListTile(
        key: key,
        title: Text(envelope.name),
        subtitle: const Text(
          'opening balances pending distribution',
          key: Key('openingBalanceNotice'),
        ),
        trailing: Text(_formatUsdCents(envelope.balanceUsd)),
        onTap: () => context.push('/distribute?source=apertura'),
      );
    }

    final metadata = envelope.metadata;
    return switch (metadata) {
      GoalLineMetadata() => _GoalLineEnvelopeTile(
        key: key,
        envelope: envelope,
        metadata: metadata,
      ),
      CapMetadata() => _CapEnvelopeTile(
        key: key,
        envelope: envelope,
        metadata: metadata,
      ),
      NoMetadata() => ListTile(
        key: key,
        leading: _envelopeLeading(envelope),
        title: Text(envelope.name),
        trailing: Text(_formatUsdCents(envelope.balanceUsd)),
      ),
    };
  }
}

class _GoalLineEnvelopeTile extends StatelessWidget {
  const _GoalLineEnvelopeTile({
    super.key,
    required this.envelope,
    required this.metadata,
  });

  final PatrimonioEnvelope envelope;
  final GoalLineMetadata metadata;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _envelopeLeading(envelope),
      title: Text(envelope.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(value: metadata.progressPercent / 100),
          Text(
            metadata.isOverdue
                ? 'vencida'
                : metadata.quotaPerMonthUsd > 0
                ? 'Cuota sugerida: ${_formatUsdCents(metadata.quotaPerMonthUsd)}/mes'
                : '${metadata.progressPercent}%',
          ),
        ],
      ),
      trailing: Text(_formatUsdCents(envelope.balanceUsd)),
    );
  }
}

class _CapEnvelopeTile extends StatelessWidget {
  const _CapEnvelopeTile({
    super.key,
    required this.envelope,
    required this.metadata,
  });

  final PatrimonioEnvelope envelope;
  final CapMetadata metadata;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _envelopeLeading(envelope),
      title: Text(envelope.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(value: metadata.fillPercent / 100),
          if (metadata.isOverfilled) const Text('Overfill'),
        ],
      ),
      trailing: Text(_formatUsdCents(envelope.balanceUsd)),
    );
  }
}

class _AccountGroupTile extends StatelessWidget {
  const _AccountGroupTile({required this.group});

  final PatrimonioAccountGroup group;

  @override
  Widget build(BuildContext context) {
    final isNegative = group.nativeMinorAmount < BigInt.zero;
    return ListTile(
      key: Key('accountGroup_${group.currency.value}'),
      title: Text(group.currency.value),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _formatNativeAmount(group.nativeMinorAmount, group.currency),
            key: Key('accountGroupNativeAmount_${group.currency.value}'),
            style:
                isNegative
                    ? TextStyle(color: Theme.of(context).colorScheme.error)
                    : null,
          ),
          Text(
            'Real cost: ${_formatUsdCents(group.realCostUsdCents)} · '
            "Today: ${_formatUsdCents(group.todayValueUsdCents)}"
            '${group.hasRate ? '' : ' (sin tasa)'}',
          ),
          if (isNegative)
            Text(
              'Saldo negativo — ¿falta registrar un ingreso?',
              key: Key('negativeBalanceSignal_${group.currency.value}'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
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
          'No accounts yet. Add an account to see your net worth here.',
          key: Key('patrimonioEmptyState'),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// Entry point to the Accounts catalog (#94), reached from Patrimonio so
/// users can create, edit and archive Accounts without a dedicated tab.
class _ManageAccountsAction extends StatelessWidget {
  const _ManageAccountsAction();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const Key('manageAccountsAction'),
      icon: const Icon(Icons.account_balance_wallet_outlined),
      tooltip: 'Manage accounts',
      onPressed: () => context.push('/accounts'),
    );
  }
}

/// Entry point into the Envelopes management screen (U1 slice 2, #95) — the
/// only place from which user Envelopes can be created, edited or archived.
class _ManageEnvelopesAction extends StatelessWidget {
  const _ManageEnvelopesAction();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const Key('manageEnvelopesAction'),
      icon: const Icon(Icons.category_outlined),
      tooltip: 'Manage envelopes',
      onPressed: () => context.push('/envelopes'),
    );
  }
}

/// Entry point to the cascade editor (#111): always available from Patrimonio,
/// independent of Stage/Opening balance. The cascade is the configuration that
/// decides where money goes; it should be editable in cold, not just when
/// distributing.
class _EditCascadeAction extends StatelessWidget {
  const _EditCascadeAction();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const Key('editCascadeAction'),
      icon: const Icon(Icons.waterfall_chart_outlined),
      tooltip: 'Edit cascade',
      onPressed: () => context.push('/distribute/edit'),
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
      onPressed:
          () => showDialog<void>(
            context: context,
            builder: (context) => const _RecordRatesDialog(),
          ),
    );
  }
}

class _RecordRatesDialog extends ConsumerStatefulWidget {
  const _RecordRatesDialog();

  @override
  ConsumerState<_RecordRatesDialog> createState() => _RecordRatesDialogState();
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

      ref.invalidate(patrimonioSnapshotProvider);
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
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
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
