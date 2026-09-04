import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:patrimonio/patrimonio.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/domain/rate_observation.dart';
import 'package:tasas/domain/rate_resolver.dart';

import '../../../../providers/tasas_providers.dart';
import '../../../../ui/theme/app_icons.dart';
import '../../../../ui/theme/app_theme.dart';
import '../../../backup/ui/widgets/restore_backup_button.dart';
import '../../../debts/application/debts_providers.dart';
import '../../application/patrimonio_providers.dart';

String _formatUsdCents(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';

/// Human-readable provenance for a resolved Rate suggestion (#175), same
/// convention as the account-creation and quick-add forms (ADR-0018 "la app
/// siempre anuncia con qué valoró").
String _sourceLabel(String source) => switch (source) {
  'dolarapi:oficial' => 'DolarApi (oficial)',
  'binancep2p:ask' => 'Binance P2P',
  'dolarapi:paralelo' => 'DolarApi',
  _ => 'manual',
};

String _formatRateDate(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

const _rateMonthAbbreviations = [
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

String _formatShortRateDate(DateTime date) =>
    '${date.day} ${_rateMonthAbbreviations[date.month - 1]}';

bool _isRateFromToday(DateTime date) {
  final now = DateTime.now();
  return date.year == now.year &&
      date.month == now.month &&
      date.day == now.day;
}

/// Same "hace N h" convention as the quick-add capture sheet's rate
/// disclosure (ADR-0018 §4) — `manual:*` is always "hoy" since a manual
/// entry is the user typing today's number, not an hours-old observation.
String _rateRecency(DateTime observedLocal, String source) {
  if (source == 'manual:paralelo' || source == 'manual:bcv') return 'hoy';
  final hours = DateTime.now().difference(observedLocal).inHours;
  return 'hace $hours h';
}

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
          _OverflowMenu(),
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
    final debtsAsync = ref.watch(debtsSnapshotProvider);

    return snapshotAsync.when(
      data:
          (snapshot) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Header(snapshot: snapshot),
              const SizedBox(height: 24),
              const Text(
                'Sobres (a costo congelado)',
                key: Key('envelopesFrozenCostLabel'),
              ),
              for (final envelope in snapshot.envelopes)
                _EnvelopeTile(envelope: envelope),
              const SizedBox(height: 24),
              for (final group in snapshot.accountGroups)
                _AccountGroupTile(group: group),
              if (debtsAsync.hasValue && debtsAsync.value!.personas.isNotEmpty)
                _DebtsLineTile(
                  globalNetoUsdCents: debtsAsync.value!.globalNetoUsdCents,
                ),
            ],
          ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => Center(child: Text('Error: $error')),
    );
  }
}

/// The Deudas segregation (#207, ADR-0022): Debt Accounts are excluded from
/// [PatrimonioSnapshot.accountGroups] at the app layer (patrimonio_providers)
/// so they never surface as their own currency group — this single line
/// stands in for all of them, linking to the Debts screen for the per-person
/// breakdown.
class _DebtsLineTile extends StatelessWidget {
  const _DebtsLineTile({required this.globalNetoUsdCents});

  final int globalNetoUsdCents;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: const Key('debtsLine'),
      title: Text('Deudas · ${_formatUsdCents(globalNetoUsdCents)}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/debts'),
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
          if (group.currency != CurrencyCode('USD')) ...[
            _RateDisclosureLine(
              label: 'Paralelo',
              currency: group.currency,
              rate: group.hasRate ? group.parallelRate : null,
              keyPrefix: 'parallel',
            ),
            _RateDisclosureLine(
              label: 'BCV',
              currency: group.currency,
              rate: group.hasBcvRate ? group.bcvRate : null,
              keyPrefix: 'bcv',
            ),
          ],
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

/// One rate disclosure line for a currency group (#176, ADR-0018 §4): the
/// app must always announce what it valued with. Mirrors the quick-add
/// capture sheet's announcement — value · source · age — and its stale
/// warning, but never blocks: a missing or stale rate is declared, not
/// hidden behind a mute number.
class _RateDisclosureLine extends StatelessWidget {
  const _RateDisclosureLine({
    required this.label,
    required this.currency,
    required this.rate,
    required this.keyPrefix,
  });

  final String label;
  final CurrencyCode currency;
  final RateObservationView? rate;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final rate = this.rate;
    if (rate == null) {
      return Text(
        '$label: sin cotización disponible para ${currency.value}',
        key: Key('${keyPrefix}RateUnavailable_${currency.value}'),
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }

    final observedLocal = rate.observedAt.toLocal();
    final rateText = rate.nativePerUsd.toStringAsFixed(2);

    if (_isRateFromToday(observedLocal)) {
      return Text(
        '$label: $rateText ${currency.value}/USD · '
        '${_sourceLabel(rate.source)}, '
        '${_rateRecency(observedLocal, rate.source)}',
        key: Key('${keyPrefix}RateAnnouncement_${currency.value}'),
      );
    }

    return Text(
      '$label: ⚠ sin actualizar desde el '
      '${_formatShortRateDate(observedLocal)} — valorando a $rateText '
      '${currency.value}/USD',
      key: Key('${keyPrefix}StaleWarning_${currency.value}'),
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Text(
              'Todavía no hay cuentas',
              key: Key('patrimonioEmptyState'),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            _CloudCopyEmptyStateLink(),
            SizedBox(height: 16),
            RestoreBackupButton(),
          ],
        ),
      ),
    );
  }
}

/// Offers the connect-first path (#226, ADR-0023 §6, #245) right where a
/// just-installed user lands: before creating a single Account, they can
/// connect the Google Drive that already has their other phone's data. The
/// prominent path in the empty state — the restore-from-file path
/// ([RestoreBackupButton]) is secondary, since Drive is what most users
/// coming from another phone actually want.
class _CloudCopyEmptyStateLink extends StatelessWidget {
  const _CloudCopyEmptyStateLink();

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      key: const Key('cloudCopyEmptyStateLink'),
      onPressed: () => context.push('/cloud-copy'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Conectar tu Google Drive', textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(
            'Si ya usas Cuentaria en otro teléfono, tus datos bajan solos',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
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
            builder: (context) => const RecordRatesDialog(),
          ),
    );
  }
}

/// Overflow menu (#192, ADR-0021): a single ⋮ next to the four existing
/// icons rather than a fifth one, since Respaldo and Deudas (#205) are
/// reached rarely — unlike the daily-use actions it sits beside.
class _OverflowMenu extends StatelessWidget {
  const _OverflowMenu();

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      key: const Key('patrimonioOverflowMenu'),
      onSelected: (value) {
        if (value == 'backup') context.push('/backup');
        if (value == 'debts') context.push('/debts');
        if (value == 'cloudCopy') context.push('/cloud-copy');
      },
      itemBuilder:
          (context) => const [
            PopupMenuItem(
              key: Key('backupMenuItem'),
              value: 'backup',
              child: Text('Respaldo'),
            ),
            PopupMenuItem(
              key: Key('debtsMenuItem'),
              value: 'debts',
              child: Text('Deudas'),
            ),
            PopupMenuItem(
              key: Key('cloudCopyMenuItem'),
              value: 'cloudCopy',
              child: Text('Copia en tu nube'),
            ),
          ],
    );
  }
}

class RecordRatesDialog extends ConsumerStatefulWidget {
  const RecordRatesDialog({super.key});

  @override
  ConsumerState<RecordRatesDialog> createState() => RecordRatesDialogState();
}

class RecordRatesDialogState extends ConsumerState<RecordRatesDialog> {
  static final _currency = CurrencyCode('VES');

  final _bcvController = TextEditingController();
  final _paraleloController = TextEditingController();
  Resolution? _suggestedBcv;
  Resolution? _suggestedParalelo;
  bool _bcvPrefilled = false;
  bool _paraleloPrefilled = false;
  String? _error;
  bool _isSaving = false;

  @override
  void dispose() {
    _bcvController.dispose();
    _paraleloController.dispose();
    super.dispose();
  }

  /// Pre-fills each field from the Rate Resolution Chain (#166) the first
  /// time its suggestion resolves — [_bcvPrefilled]/[_paraleloPrefilled]
  /// keep it from clobbering text the user is already editing on a later
  /// rebuild. A currency with no automatic source just leaves the field
  /// empty, unchanged from today's behavior.
  void _prefill(Resolution? bcv, Resolution? paralelo) {
    if (!_bcvPrefilled) {
      _bcvPrefilled = true;
      _suggestedBcv = bcv;
      if (bcv != null) _bcvController.text = bcv.nativePerUsd.toString();
    }
    if (!_paraleloPrefilled) {
      _paraleloPrefilled = true;
      _suggestedParalelo = paralelo;
      if (paralelo != null) {
        _paraleloController.text = paralelo.nativePerUsd.toString();
      }
    }
  }

  Future<void> _save() async {
    final bcvRate = Decimal.tryParse(_bcvController.text);
    final paraleloRate = Decimal.tryParse(_paraleloController.text);
    if (bcvRate == null || paraleloRate == null) {
      setState(() => _error = 'Enter both rates as a number.');
      return;
    }

    // Only what the user actually typed a different number for becomes an
    // observation (#175, ADR-0020 §S1-6) — accepting the Chain's suggestion
    // for one series must never fabricate a manual entry that would
    // outrank the real automatic source for the rest of the day.
    final bcvChanged = bcvRate != _suggestedBcv?.nativePerUsd;
    final paraleloChanged = paraleloRate != _suggestedParalelo?.nativePerUsd;
    if (!bcvChanged && !paraleloChanged) {
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _error = null;
      _isSaving = true;
    });

    try {
      final useCase = await ref.read(recordRateUseCaseProvider.future);
      final observedAt = DateTime.now().toUtc();

      await useCase.execute(
        bcv:
            bcvChanged
                ? RateObservation(
                  currency: _currency,
                  nativePerUsd: bcvRate,
                  observedAt: observedAt,
                  source: 'manual:bcv',
                )
                : null,
        paralelo:
            paraleloChanged
                ? RateObservation(
                  currency: _currency,
                  nativePerUsd: paraleloRate,
                  observedAt: observedAt,
                  source: 'manual:paralelo',
                )
                : null,
      );

      ref.invalidate(patrimonioSnapshotProvider);
      // Deudas values non-USD legs against the same series (#210) — a
      // registered rate must reach it too, not just Patrimonio's header.
      ref.invalidate(debtsSnapshotProvider);
      // Not rateSeriesProvider itself: on web it constructs a fresh, empty
      // InMemoryRateSeries — invalidating it would discard every previously
      // recorded observation. Re-reading the lookup providers is enough,
      // since they re-query the same (still-cached) RateSeries instance.
      ref.invalidate(latestParaleloRateProvider);
      ref.invalidate(latestOficialRateProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bcvAsync = ref.watch(latestOficialRateProvider(_currency));
    final paraleloAsync = ref.watch(latestParaleloRateProvider(_currency));
    if (bcvAsync.hasValue && paraleloAsync.hasValue) {
      _prefill(bcvAsync.value, paraleloAsync.value);
    }

    return AlertDialog(
      title: const Text('Record today\'s rates'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('bcvRateField'),
            controller: _bcvController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'BCV (VES per USD)'),
          ),
          if (_suggestedBcv != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${_sourceLabel(_suggestedBcv!.source)}, '
                '${_formatRateDate(_suggestedBcv!.observedAt.toLocal())}',
                key: const Key('suggestedBcvAnnouncement'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
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
          if (_suggestedParalelo != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${_sourceLabel(_suggestedParalelo!.source)}, '
                '${_formatRateDate(_suggestedParalelo!.observedAt.toLocal())}',
                key: const Key('suggestedParaleloAnnouncement'),
                style: Theme.of(context).textTheme.bodySmall,
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
