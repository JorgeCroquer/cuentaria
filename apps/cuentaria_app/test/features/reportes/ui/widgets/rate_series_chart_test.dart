import 'package:cuentaria_app/features/reportes/ui/widgets/rate_series_chart.dart';
import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/domain/rate_observation.dart';

RateObservation _obs({
  required String rate,
  required DateTime observedAt,
  required String source,
}) => RateObservation(
  currency: CurrencyCode('VES'),
  nativePerUsd: Decimal.parse(rate),
  observedAt: observedAt,
  source: source,
);

void main() {
  Future<void> pump(WidgetTester tester, List<RateObservation> obs) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: RateSeriesChart(observations: obs))),
    );
  }

  testWidgets('renders one line per distinct source', (tester) async {
    await pump(tester, [
      _obs(
        rate: '900',
        observedAt: DateTime.utc(2026, 8, 1),
        source: 'manual:paralelo',
      ),
      _obs(
        rate: '845',
        observedAt: DateTime.utc(2026, 8, 2),
        source: 'binancep2p:ask',
      ),
      _obs(
        rate: '840',
        observedAt: DateTime.utc(2026, 8, 3),
        source: 'binancep2p:ask',
      ),
      _obs(
        rate: '800',
        observedAt: DateTime.utc(2026, 8, 4),
        source: 'dolarapi:paralelo',
      ),
    ]);

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.lineBarsData, hasLength(3));
  });

  testWidgets('shows an empty state when there are no observations', (
    tester,
  ) async {
    await pump(tester, []);

    expect(find.byType(LineChart), findsNothing);
    expect(find.text('Sin observaciones de tasa'), findsOneWidget);
  });
}
