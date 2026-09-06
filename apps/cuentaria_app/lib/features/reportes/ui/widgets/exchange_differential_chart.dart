import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:reportes/reportes.dart';

/// Últimos 12 meses del Diferencial cambiario (#264, ADR-0024 §7): realizado
/// as bars, no realizado as a line overlay sharing the same USD-cents scale
/// so the two stay visually comparable. [FlSpot.nullSpot] renders an honest
/// gap wherever [ExchangeDifferentialPoint.noRealizadoUsdCents] is null —
/// same convention as [PatrimonioEnTiempoChart]'s market-value line.
class ExchangeDifferentialChart extends StatelessWidget {
  const ExchangeDifferentialChart({super.key, required this.points});

  final List<ExchangeDifferentialPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const Center(child: Text('Sin datos de diferencial'));
    }

    final values = [
      0.0,
      for (final point in points) point.realizadoUsdCents / 100,
      for (final point in points)
        if (point.noRealizadoUsdCents case final value?) value / 100,
    ];
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final minY = values.reduce((a, b) => a < b ? a : b);

    final lineSpots = [
      for (var i = 0; i < points.length; i++)
        if (points[i].noRealizadoUsdCents case final value?)
          FlSpot(i.toDouble(), value / 100)
        else
          FlSpot.nullSpot,
    ];

    return SizedBox(
      height: 160,
      child: Stack(
        children: [
          BarChart(
            BarChartData(
              minY: minY,
              maxY: maxY,
              alignment: BarChartAlignment.spaceEvenly,
              titlesData: const FlTitlesData(show: false),
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(enabled: false),
              barGroups: [
                for (var i = 0; i < points.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: points[i].realizadoUsdCents / 100,
                        color: Theme.of(context).colorScheme.primary,
                        width: 10,
                      ),
                    ],
                  ),
              ],
            ),
          ),
          LineChart(
            LineChartData(
              minX: -0.5,
              maxX: points.length - 0.5,
              minY: minY,
              maxY: maxY,
              titlesData: const FlTitlesData(show: false),
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              lineTouchData: const LineTouchData(enabled: false),
              lineBarsData: [
                LineChartBarData(
                  color: Colors.teal,
                  isCurved: false,
                  dotData: const FlDotData(show: true),
                  spots: lineSpots,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
