import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:reportes/reportes.dart';

const _lineColors = [
  Colors.blue,
  Colors.teal,
  Colors.orange,
  Colors.purple,
  Colors.green,
  Colors.brown,
];

/// Line chart of the last 12 Debt Points (#265, mirrors
/// [PatrimonioEnTiempoChart]): one line per counterparty that appears in at
/// least one of [points], using [FlSpot.nullSpot] for the months they had
/// no balance — an honest gap, never a fabricated zero.
class DeudaPorPersonaChart extends StatelessWidget {
  const DeudaPorPersonaChart({super.key, required this.points});

  final List<DebtPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const Center(child: Text('Sin datos de deudas'));
    }

    final personNames =
        <String>{
            for (final point in points)
              for (final persona in point.personas) persona.personName,
          }.toList()
          ..sort();

    PersonDebtPoint? personaAt(int monthIndex, String name) {
      for (final persona in points[monthIndex].personas) {
        if (persona.personName == name) return persona;
      }
      return null;
    }

    return SizedBox(
      height: 240,
      child: LineChart(
        LineChartData(
          lineBarsData: [
            for (var i = 0; i < personNames.length; i++)
              LineChartBarData(
                color: _lineColors[i % _lineColors.length],
                isCurved: false,
                dotData: const FlDotData(show: true),
                spots: [
                  for (var j = 0; j < points.length; j++)
                    if (personaAt(j, personNames[i]) case final persona?)
                      FlSpot(j.toDouble(), persona.netoUsdCents / 100)
                    else
                      FlSpot.nullSpot,
                ],
              ),
          ],
        ),
      ),
    );
  }
}
