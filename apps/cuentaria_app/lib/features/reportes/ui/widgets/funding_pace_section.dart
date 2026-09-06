import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reportes/reportes.dart';

import '../../application/funding_pace_providers.dart';

String _formatUsdCents(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';

String _statusLabel(FundingPaceStatus status) => switch (status) {
  FundingPaceStatus.onPace => 'al ritmo',
  FundingPaceStatus.behind => 'atrasado',
  FundingPaceStatus.goalReached => 'meta alcanzada',
};

/// Aportes a metas (ADR-0024, #263): one row per Envelope with a Funding
/// Target, comparing this Report Month's aporte against what the
/// [FundingPaceEngine] says it takes per month to arrive on time. Today's
/// progress toward the goal already lives in Patrimonio and is not repeated
/// here.
class FundingPaceSection extends ConsumerWidget {
  const FundingPaceSection({super.key, required this.month});

  final ReportMonth month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultAsync = ref.watch(fundingPaceProvider(month));

    return Card(
      key: const Key('reportSection_aportesAMetas'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Aportes a metas',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            resultAsync.when(
              data: (result) {
                if (result.isEmpty) {
                  return const Text('Aún no hay datos para este mes');
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final envelopeResult in result.rows)
                      _FundingPaceEnvelopeTile(result: envelopeResult),
                  ],
                );
              },
              loading:
                  () => const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              error: (error, stackTrace) => Text('No se pudo cargar: $error'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FundingPaceEnvelopeTile extends StatelessWidget {
  const _FundingPaceEnvelopeTile({required this.result});

  final FundingPaceEnvelopeResult result;

  @override
  Widget build(BuildContext context) {
    final row = result.row;
    final requiredPerMonth = row.requiredPerMonthUsdCents;
    final status = row.status;

    final summary = StringBuffer(
      '${row.name} · aportado ${_formatUsdCents(row.contributedThisMonthUsdCents)}',
    );
    if (requiredPerMonth != null && status != null) {
      summary.write(
        ' · necesitás ${_formatUsdCents(requiredPerMonth)}/mes · '
        '${_statusLabel(status)}',
      );
    }

    return Padding(
      key: Key('fundingPaceRow_${row.envelopeId.value}'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(summary.toString()),
          const SizedBox(height: 8),
          _MonthlyHistoryChart(
            amountsUsdCents: result.monthlyContributionsUsdCents,
          ),
        ],
      ),
    );
  }
}

/// Last 12 months of aportes for one Envelope, oldest first — [fl_chart]
/// has no built-in "sparkline of bars" widget, so this is the same bare
/// `BarChart` shape `SpendingByEnvelopeSection` already uses, just vertical.
class _MonthlyHistoryChart extends StatelessWidget {
  const _MonthlyHistoryChart({required this.amountsUsdCents});

  final List<int> amountsUsdCents;

  @override
  Widget build(BuildContext context) {
    final maxAmount = amountsUsdCents.fold(
      0,
      (max, amount) => amount > max ? amount : max,
    );

    return SizedBox(
      height: 60,
      child: BarChart(
        BarChartData(
          maxY: maxAmount <= 0 ? 1 : maxAmount.toDouble(),
          alignment: BarChartAlignment.spaceAround,
          titlesData: const FlTitlesData(show: false),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(enabled: false),
          barGroups: [
            for (var i = 0; i < amountsUsdCents.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: amountsUsdCents[i].toDouble(),
                    color: Theme.of(context).colorScheme.primary,
                    width: 8,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
