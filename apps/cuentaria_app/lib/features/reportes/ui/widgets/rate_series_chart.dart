import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:tasas/domain/rate_observation.dart';

/// Colors per source (#261) — Binance P2P in orange tones (an executable
/// price), DolarApi in blue/teal tones (a third-party average), anything
/// else (`manual:*`) in grey, consistent with the "manual" label used
/// elsewhere for rate provenance.
const _sourceColors = {
  'binancep2p:ask': Colors.deepOrange,
  'binancep2p:bid': Colors.orange,
  'dolarapi:paralelo': Colors.blue,
  'dolarapi:oficial': Colors.teal,
};

Color _colorFor(String source) => _sourceColors[source] ?? Colors.grey;

/// Line chart of [observations] for a single currency, one line per source
/// (#261) — the Rate Series screen's own currency selector already scopes
/// [observations] to a single [RateObservation.currency] and to the last 12
/// months, so this widget only groups by source and plots.
class RateSeriesChart extends StatelessWidget {
  const RateSeriesChart({super.key, required this.observations});

  final List<RateObservation> observations;

  @override
  Widget build(BuildContext context) {
    if (observations.isEmpty) {
      return const Center(child: Text('Sin observaciones de tasa'));
    }

    final bySource = <String, List<RateObservation>>{};
    for (final observation in observations) {
      bySource.putIfAbsent(observation.source, () => []).add(observation);
    }

    return SizedBox(
      height: 240,
      child: LineChart(
        LineChartData(
          lineBarsData: [
            for (final entry in bySource.entries)
              LineChartBarData(
                color: _colorFor(entry.key),
                isCurved: false,
                dotData: const FlDotData(show: true),
                spots: [
                  for (final observation in entry.value)
                    FlSpot(
                      observation.observedAt.millisecondsSinceEpoch.toDouble(),
                      double.parse(observation.nativePerUsd.toString()),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
