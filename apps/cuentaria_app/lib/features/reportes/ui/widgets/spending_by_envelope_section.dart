import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reportes/reportes.dart';

import '../../application/spending_by_envelope_providers.dart';
import 'month_selector.dart';

String _formatUsdCents(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';

/// Gasto por sobre (ADR-0024, #259): the first live Reportes section. Wired
/// end-to-end to [spendingByEnvelopeProvider] — the pure
/// `SpendingByEnvelopeEngine`, not this widget, decides what counts as
/// flow — so recording a new expense refreshes it the same way every other
/// EventBus-reactive provider in the app does. Keeps the same title and
/// empty-state text as the [ReportSection] placeholder it replaces, so an
/// empty month reads identically to the other five still-unfilled sections.
class SpendingByEnvelopeSection extends ConsumerWidget {
  const SpendingByEnvelopeSection({super.key, required this.month});

  final ReportMonth month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultAsync = ref.watch(spendingByEnvelopeProvider(month));

    return Card(
      key: const Key('reportSection_gastoPorSobre'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Gasto por sobre',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            resultAsync.when(
              data: (result) {
                if (result.isEmpty) {
                  return const Text('Aún no hay datos para este mes');
                }
                return _SpendingBody(
                  result: result,
                  previousMonth: month.previousMonth,
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

class _SpendingBody extends StatelessWidget {
  const _SpendingBody({required this.result, required this.previousMonth});

  final SpendingByEnvelopeResult result;
  final ReportMonth previousMonth;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _formatUsdCents(result.totalUsdCents),
          key: const Key('spendingByEnvelopeTotal'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        if (result.rows.isNotEmpty) _SpendingBarChart(rows: result.rows),
        for (final row in result.rows)
          _SpendingRowTile(row: row, previousMonth: previousMonth),
        if (result.adjustments != null)
          _SpendingRowTile(
            row: result.adjustments!,
            previousMonth: previousMonth,
          ),
        if (result.differential != null)
          _SpendingRowTile(
            row: result.differential!,
            previousMonth: previousMonth,
          ),
      ],
    );
  }
}

/// Horizontal bars (ADR-0024 §7), highest spend first — [rows] arrives
/// already sorted by [spendingByEnvelopeProvider]. fl_chart has no native
/// horizontal orientation, so the rods are drawn vertical and the whole
/// plot rotated a quarter turn; the readable name/amount/comparison lives in
/// [_SpendingRowTile] below it, not on the (now sideways) chart labels.
class _SpendingBarChart extends StatelessWidget {
  const _SpendingBarChart({required this.rows});

  final List<SpendingRow> rows;

  @override
  Widget build(BuildContext context) {
    final maxAmount =
        rows
            .map((row) => row.amountUsdCents)
            .reduce((a, b) => a > b ? a : b)
            .toDouble();

    return SizedBox(
      height: rows.length * 28.0 + 16,
      child: RotatedBox(
        quarterTurns: 3,
        child: BarChart(
          BarChartData(
            maxY: maxAmount,
            alignment: BarChartAlignment.spaceAround,
            titlesData: const FlTitlesData(show: false),
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            barTouchData: BarTouchData(enabled: false),
            barGroups: [
              for (var i = 0; i < rows.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: rows[i].amountUsdCents.toDouble(),
                      color: Theme.of(context).colorScheme.primary,
                      width: 16,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpendingRowTile extends StatelessWidget {
  const _SpendingRowTile({required this.row, required this.previousMonth});

  final SpendingRow row;
  final ReportMonth previousMonth;

  @override
  Widget build(BuildContext context) {
    final change = row.changePercent;
    final comparison =
        change == null
            ? null
            : '${change >= 0 ? '+' : ''}${change.round()}% vs ${monthName(previousMonth.month)}';

    return Padding(
      key: Key('spendingRow_${row.envelopeId.value}'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(row.label),
          Text(
            comparison == null
                ? _formatUsdCents(row.amountUsdCents)
                : '${_formatUsdCents(row.amountUsdCents)} · $comparison',
          ),
        ],
      ),
    );
  }
}
