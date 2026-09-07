import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reportes/reportes.dart';

import '../../application/income_by_source_providers.dart';
import 'month_selector.dart';

String _formatUsdCents(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';

/// Ingreso por fuente (ADR-0024, #262): the same live-section pattern as
/// [SpendingByEnvelopeSection] (#259), wired to [incomeBySourceProvider] — the
/// pure `IncomeBySourceEngine` decides what counts as flow, so recording a
/// new income refreshes it the same way every other EventBus-reactive
/// provider in the app does.
class IncomeBySourceSection extends ConsumerWidget {
  const IncomeBySourceSection({super.key, required this.month});

  final ReportMonth month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultAsync = ref.watch(incomeBySourceProvider(month));

    return Card(
      key: const Key('reportSection_ingresoPorFuente'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Ingreso por fuente',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            resultAsync.when(
              data: (result) {
                if (result.isEmpty) {
                  return const Text('Aún no hay datos para este mes');
                }
                return _IncomeBody(
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

class _IncomeBody extends StatelessWidget {
  const _IncomeBody({required this.result, required this.previousMonth});

  final IncomeBySourceResult result;
  final ReportMonth previousMonth;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _formatUsdCents(result.totalUsdCents),
          key: const Key('incomeBySourceTotal'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        _IncomeBarChart(rows: result.rows),
        for (final row in result.rows)
          _IncomeRowTile(row: row, previousMonth: previousMonth),
      ],
    );
  }
}

/// Horizontal bars (ADR-0024 §7), highest income first — [rows] arrives
/// already sorted by [incomeBySourceProvider]. fl_chart has no native
/// horizontal orientation, so the rods are drawn vertical and the whole
/// plot rotated a quarter turn; the readable label/amount/comparison lives
/// in [_IncomeRowTile] below it, not on the (now sideways) chart labels.
class _IncomeBarChart extends StatelessWidget {
  const _IncomeBarChart({required this.rows});

  final List<IncomeRow> rows;

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

class _IncomeRowTile extends StatelessWidget {
  const _IncomeRowTile({required this.row, required this.previousMonth});

  final IncomeRow row;
  final ReportMonth previousMonth;

  @override
  Widget build(BuildContext context) {
    final change = row.changePercent;
    final comparison =
        change == null
            ? null
            : '${change >= 0 ? '+' : ''}${change.round()}% vs ${monthName(previousMonth.month)}';

    return Padding(
      key: Key('incomeRow_${row.label}'),
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
