import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:reportes/reportes.dart';

/// Line chart of the last 12 Net Worth Points (#260, ADR-0024 §5-6): real
/// cost (frozen, ADR-0006) is a solid line always populated; market value is
/// a dashed line that uses [FlSpot.nullSpot] wherever
/// [PatrimonioPoint.marketValueUsdCents] is null, rendering an honest gap
/// instead of a fabricated zero.
class PatrimonioEnTiempoChart extends StatelessWidget {
  const PatrimonioEnTiempoChart({super.key, required this.points});

  final List<PatrimonioPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const Center(child: Text('Sin datos de patrimonio'));
    }

    final realCostSpots = [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].realCostUsdCents / 100),
    ];

    final marketValueSpots = [
      for (var i = 0; i < points.length; i++)
        if (points[i].marketValueUsdCents case final value?)
          FlSpot(i.toDouble(), value / 100)
        else
          FlSpot.nullSpot,
    ];

    return SizedBox(
      height: 240,
      child: LineChart(
        LineChartData(
          lineBarsData: [
            LineChartBarData(
              color: Colors.blue,
              isCurved: false,
              dotData: const FlDotData(show: true),
              spots: realCostSpots,
            ),
            LineChartBarData(
              color: Colors.teal,
              dashArray: const [6, 4],
              isCurved: false,
              dotData: const FlDotData(show: true),
              spots: marketValueSpots,
            ),
          ],
        ),
      ),
    );
  }
}
