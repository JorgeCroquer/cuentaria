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

final _usd = CurrencyCode('USD');

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

/// One rate chip's value line (#279): value · currency/USD · age, or a
/// stale/unavailable declaration — same disclosure convention as the
/// capture sheet (ADR-0018 §4), condensed to fit a chip instead of a full
/// per-currency paragraph.
String _rateChipValueText(RateObservationView? rate, CurrencyCode currency) {
  if (rate == null) return 'sin cotización disponible';
  final observedLocal = rate.observedAt.toLocal();
  final rateText = rate.nativePerUsd.toStringAsFixed(2);
  if (_isRateFromToday(observedLocal)) {
    return '$rateText ${currency.value}/USD · '
        '${_rateRecency(observedLocal, rate.source)}';
  }
  return '$rateText ${currency.value}/USD · sin actualizar desde el '
      '${_formatShortRateDate(observedLocal)}';
}

String _formatNativeAmount(BigInt minorAmount, CurrencyCode currency) {
  final decimal =
      (Decimal.fromBigInt(minorAmount) / Decimal.fromInt(100)).toDecimal();
  return '${decimal.toStringAsFixed(2)} ${currency.value}';
}

String _currencySymbol(CurrencyCode currency) => switch (currency.value) {
  'USD' => '\$',
  'VES' => 'Bs',
  _ => currency.value,
};

/// The first non-USD currency group, if any (#279): the rate chips disclose
/// the observation that values it — in practice there is at most one
/// foreign currency in play at a time.
PatrimonioAccountGroup? _primaryForeignGroup(
  List<PatrimonioAccountGroup> groups,
) {
  for (final group in groups) {
    if (group.currency != _usd) return group;
  }
  return null;
}

/// The icon a user Envelope was tagged with in the management screen (#95),
/// or the catalog default when none was chosen — the Sobres card always
/// shows an avatar (#279).
Icon _envelopeIcon(PatrimonioEnvelope envelope) {
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

/// Patrimonio screen (#82, redesigned #279 "Héroe y tarjetas"): a single
/// hero figure (today's value), rate chips, and the Sin asignar/Sobres/
/// Cuentas/Deudas cards — all driven end-to-end by [patrimonioSnapshotProvider]
/// — the engine, not the widget tree, does the valuation math. Shows a
/// guidance empty state when the catalog has no accounts, rather than a
/// spinner or a bare zero.
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
        actions: const [_ReportsAction(), _OverflowMenu()],
      ),
      body: snapshotAsync.when(
        data: (snapshot) {
          if (snapshot.accountGroups.isEmpty) {
            return const _EmptyState();
          }
          return const _PatrimonioBody();
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error:
            (error, stackTrace) =>
                Center(child: Text('No se pudo cargar: $error')),
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
      data: (snapshot) {
        final userEnvelopes =
            snapshot.envelopes
                .where((e) => e.role == EnvelopeRoleView.user)
                .toList();
        final unassigned = snapshot.envelopes
            .cast<PatrimonioEnvelope?>()
            .firstWhere(
              (e) => e!.role == EnvelopeRoleView.stage,
              orElse: () => null,
            );
        final opening = snapshot.envelopes
            .cast<PatrimonioEnvelope?>()
            .firstWhere(
              (e) => e!.role == EnvelopeRoleView.opening,
              orElse: () => null,
            );

        final children = <Widget>[_Hero(snapshot: snapshot)];

        final foreignGroup = _primaryForeignGroup(snapshot.accountGroups);
        if (foreignGroup != null &&
            (foreignGroup.parallelRate != null ||
                foreignGroup.bcvRate != null)) {
          children
            ..add(const SizedBox(height: AppSpacing.lg))
            ..add(_RateChipsRow(group: foreignGroup));
        }

        if (unassigned != null || opening != null) {
          children
            ..add(const SizedBox(height: AppSpacing.lg))
            ..add(_UnassignedCard(stage: unassigned, opening: opening));
        }

        if (userEnvelopes.isNotEmpty) {
          children
            ..add(const SizedBox(height: AppSpacing.md))
            ..add(_EnvelopesCard(envelopes: userEnvelopes));
        }

        if (snapshot.accountGroups.isNotEmpty) {
          children
            ..add(const SizedBox(height: AppSpacing.md))
            ..add(_AccountsCard(groups: snapshot.accountGroups));
        }

        if (debtsAsync.hasValue && debtsAsync.value!.personas.isNotEmpty) {
          children
            ..add(const SizedBox(height: AppSpacing.md))
            ..add(
              _DebtsCard(
                globalNetoUsdCents: debtsAsync.value!.globalNetoUsdCents,
              ),
            );
        }

        return ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: children,
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error:
          (error, stackTrace) =>
              Center(child: Text('No se pudo cargar: $error')),
    );
  }
}

/// The hero figure (#279): a single large "valor hoy" number, with real
/// cost and unrealized P&L folded into one secondary line below it — the
/// P&L paints [ColorScheme.error] when negative, [ColorScheme.primary]
/// when positive, per ADR-0016 §5 ("the parallel rate values"). The BCV
/// reference moves out of the hero entirely, into the rate chips below.
class _Hero extends StatelessWidget {
  const _Hero({required this.snapshot});

  final PatrimonioSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final pnl = snapshot.unrealizedPnlUsdCents;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Valor hoy (paralelo)',
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          _formatUsdCents(snapshot.todayValueUsdCents),
          key: const Key('todayValueAmount'),
          style: textTheme.displaySmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Costo real '),
            Text(
              _formatUsdCents(snapshot.realCostUsdCents),
              key: const Key('realCostAmount'),
            ),
            const Text(' · '),
            Text(
              _formatUsdCents(pnl),
              key: const Key('unrealizedPnlAmount'),
              style: TextStyle(
                color: pnl < 0 ? colorScheme.error : colorScheme.primary,
              ),
            ),
            const Text(' no realizado'),
          ],
        ),
        if (snapshot.hasMissingRate) ...[
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'sin tasa — algunas monedas aún no tienen tasa',
            key: Key('missingRateFlag'),
          ),
        ],
      ],
    );
  }
}

/// Rate disclosure chips (#279, ADR-0018 §4): the app must always announce
/// what it valued with — condensed here to Paralelo/BCV chips fed by the
/// same [PatrimonioAccountGroup.parallelRate]/[PatrimonioAccountGroup.bcvRate]
/// observations that used to render as a per-currency paragraph.
class _RateChipsRow extends StatelessWidget {
  const _RateChipsRow({required this.group});

  final PatrimonioAccountGroup group;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final chipShape = StadiumBorder(
      side: BorderSide(color: colorScheme.outlineVariant),
    );

    return Wrap(
      key: const Key('rateChipsRow'),
      alignment: WrapAlignment.center,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        Chip(
          shape: chipShape,
          backgroundColor: Colors.transparent,
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Paralelo ', style: TextStyle(color: colorScheme.primary)),
              Flexible(
                child: Text(
                  _rateChipValueText(group.parallelRate, group.currency),
                  key: const Key('paraleloRateAmount'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Chip(
          shape: chipShape,
          backgroundColor: Colors.transparent,
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('BCV '),
              Flexible(
                child: Text(
                  _rateChipValueText(group.bcvRate, group.currency),
                  key: const Key('bcvReferenceAmount'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "Sin asignar" action card (#279): Stage's balance with a one-touch
/// [FilledButton] into the distribute flow (C2). Apertura folds in as a
/// pending-distribution subline instead of its own row once it carries a
/// balance (S2).
class _UnassignedCard extends StatelessWidget {
  const _UnassignedCard({this.stage, this.opening});

  final PatrimonioEnvelope? stage;
  final PatrimonioEnvelope? opening;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final onContainer = colorScheme.onSecondaryContainer;
    final stage = this.stage;
    final opening = this.opening;

    return Card(
      color: colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (stage != null)
                    Text(
                      'Sin asignar · ${_formatUsdCents(stage.balanceUsd)}',
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(color: onContainer),
                    ),
                  if (opening != null)
                    InkWell(
                      key: const Key('openingBalanceNotice'),
                      onTap: () => context.push('/distribute?source=apertura'),
                      child: Text(
                        '+ ${_formatUsdCents(opening.balanceUsd)} de '
                        'apertura por repartir',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: onContainer),
                      ),
                    ),
                ],
              ),
            ),
            if (stage != null) ...[
              const SizedBox(width: AppSpacing.md),
              FilledButton(
                key: const Key('repartirButton'),
                onPressed: () => context.push('/distribute'),
                child: const Text('Repartir'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The Sobres card (S2, #83, #279): user Envelopes at frozen real cost
/// (ADR-0006) — Stage/Apertura live in [_UnassignedCard] instead, and
/// Diferencial/Ajustes never reach here (the engine excludes them, ADR-0015).
class _EnvelopesCard extends StatelessWidget {
  const _EnvelopesCard({required this.envelopes});

  final List<PatrimonioEnvelope> envelopes;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xs,
            ),
            child: Text(
              'SOBRES',
              key: const Key('envelopesFrozenCostLabel'),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          for (final envelope in envelopes) _EnvelopeRow(envelope: envelope),
        ],
      ),
    );
  }
}

class _EnvelopeRow extends StatelessWidget {
  const _EnvelopeRow({required this.envelope});

  final PatrimonioEnvelope envelope;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isNegative = envelope.balanceUsd < 0;
    final amountStyle = TextStyle(
      color: isNegative ? colorScheme.error : null,
      fontWeight: isNegative ? FontWeight.w500 : null,
    );
    final metadata = envelope.metadata;

    return ListTile(
      key: Key('envelope_${envelope.id.value}'),
      leading: CircleAvatar(child: _envelopeIcon(envelope)),
      title: Text(envelope.name),
      subtitle: switch (metadata) {
        GoalLineMetadata() => Column(
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
        CapMetadata() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: metadata.fillPercent / 100),
            if (metadata.isOverfilled) const Text('Sobrellenado'),
          ],
        ),
        NoMetadata() => null,
      },
      trailing: Text(_formatUsdCents(envelope.balanceUsd), style: amountStyle),
    );
  }
}

/// The Cuentas card (ADR-0016, #279): one row per currency group — native
/// balance as the title, a "hoy · costo" subline only when they diverge
/// (or the currency lacks a rate), and a chevron into Accounts management.
class _AccountsCard extends StatelessWidget {
  const _AccountsCard({required this.groups});

  final List<PatrimonioAccountGroup> groups;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xs,
            ),
            child: Text(
              'CUENTAS',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          for (final group in groups) _AccountGroupRow(group: group),
        ],
      ),
    );
  }
}

class _AccountGroupRow extends StatelessWidget {
  const _AccountGroupRow({required this.group});

  final PatrimonioAccountGroup group;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isNegative = group.nativeMinorAmount < BigInt.zero;
    final showValueLine =
        group.todayValueUsdCents != group.realCostUsdCents || !group.hasRate;

    return ListTile(
      key: Key('accountGroup_${group.currency.value}'),
      leading: CircleAvatar(child: Text(_currencySymbol(group.currency))),
      title: Text(
        _formatNativeAmount(group.nativeMinorAmount, group.currency),
        key: Key('accountGroupNativeAmount_${group.currency.value}'),
        style: isNegative ? TextStyle(color: colorScheme.error) : null,
      ),
      subtitle:
          (showValueLine || isNegative)
              ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showValueLine)
                    Text(
                      'hoy ${_formatUsdCents(group.todayValueUsdCents)} · '
                      'costo ${_formatUsdCents(group.realCostUsdCents)}'
                      '${group.hasRate ? '' : ' (sin tasa)'}',
                    ),
                  if (isNegative)
                    Text(
                      'Saldo negativo — ¿falta registrar un ingreso?',
                      key: Key('negativeBalanceSignal_${group.currency.value}'),
                      style: TextStyle(color: colorScheme.error),
                    ),
                ],
              )
              : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/accounts'),
    );
  }
}

/// The Deudas segregation (#207, ADR-0022): Debt Accounts are excluded from
/// [PatrimonioSnapshot.accountGroups] at the app layer (patrimonio_providers)
/// so they never surface as their own currency group — this card stands in
/// for all of them, linking to the Debts screen for the per-person
/// breakdown.
class _DebtsCard extends StatelessWidget {
  const _DebtsCard({required this.globalNetoUsdCents});

  final int globalNetoUsdCents;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        key: const Key('debtsLine'),
        title: Text('Deudas · ${_formatUsdCents(globalNetoUsdCents)}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/debts'),
      ),
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

/// Entry point to Reportes (#258), kept as a visible AppBar action next to
/// the overflow menu (#279) — daily-use enough to not bury behind ⋮.
class _ReportsAction extends StatelessWidget {
  const _ReportsAction();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const Key('reportsAction'),
      icon: const Icon(Icons.bar_chart_outlined),
      tooltip: 'Reportes',
      onPressed: () => context.push('/reports'),
    );
  }
}

/// Overflow menu (#192, ADR-0021, redesigned #279): the AppBar now shows
/// only Reportes and this ⋮ — every other action (cuentas, sobres, cascada,
/// tasas, respaldo, deudas, copia en la nube) moves in here, same texts and
/// destinations as when they were individual icons.
class _OverflowMenu extends StatelessWidget {
  const _OverflowMenu();

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      key: const Key('patrimonioOverflowMenu'),
      onSelected: (value) {
        switch (value) {
          case 'accounts':
            context.push('/accounts');
          case 'envelopes':
            context.push('/envelopes');
          case 'cascade':
            context.push('/distribute/edit');
          case 'rates':
            showDialog<void>(
              context: context,
              builder: (context) => const RecordRatesDialog(),
            );
          case 'backup':
            context.push('/backup');
          case 'debts':
            context.push('/debts');
          case 'cloudCopy':
            context.push('/cloud-copy');
        }
      },
      itemBuilder:
          (context) => const [
            PopupMenuItem(
              key: Key('manageAccountsAction'),
              value: 'accounts',
              child: Text('Gestionar cuentas'),
            ),
            PopupMenuItem(
              key: Key('manageEnvelopesAction'),
              value: 'envelopes',
              child: Text('Gestionar sobres'),
            ),
            PopupMenuItem(
              key: Key('editCascadeAction'),
              value: 'cascade',
              child: Text('Editar cascada'),
            ),
            PopupMenuItem(
              key: Key('recordRatesAction'),
              value: 'rates',
              child: Text('Registrar tasas'),
            ),
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
      setState(() => _error = 'Ingresa ambas tasas como número.');
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
      title: const Text('Registrar tasas de hoy'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('bcvRateField'),
            controller: _bcvController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'BCV (VES por USD)'),
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
              labelText: 'Paralelo (VES por USD)',
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
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          key: const Key('saveRatesButton'),
          onPressed: _isSaving ? null : _save,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
