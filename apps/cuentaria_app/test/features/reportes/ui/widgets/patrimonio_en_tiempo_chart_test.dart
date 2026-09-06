import 'package:cuentaria_app/features/reportes/ui/widgets/patrimonio_en_tiempo_chart.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reportes/reportes.dart';

void main() {
  Future<void> pump(WidgetTester tester, List<PatrimonioPoint> points) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PatrimonioEnTiempoChart(points: points)),
      ),
    );
  }

  testWidgets(
    'renders a real cost line and a market value line with a gap where the '
    'overlay is null',
    (tester) async {
      await pump(tester, [
        PatrimonioPoint(
          month: ReportMonth(2026, 1),
          realCostUsdCents: 10000,
          marketValueUsdCents: 9000,
        ),
        PatrimonioPoint(
          month: ReportMonth(2026, 2),
          realCostUsdCents: 12000,
          marketValueUsdCents: null,
        ),
        PatrimonioPoint(
          month: ReportMonth(2026, 3),
          realCostUsdCents: 15000,
          marketValueUsdCents: 14000,
        ),
      ]);

      final chart = tester.widget<LineChart>(find.byType(LineChart));
      expect(chart.data.lineBarsData, hasLength(2));

      final realCost = chart.data.lineBarsData[0];
      expect(realCost.spots.map((s) => s.y), [100.0, 120.0, 150.0]);

      final marketValue = chart.data.lineBarsData[1];
      expect(marketValue.spots[0].y, 90.0);
      expect(marketValue.spots[1], FlSpot.nullSpot);
      expect(marketValue.spots[2].y, 140.0);
    },
  );

  testWidgets('a single point renders without crashing', (tester) async {
    await pump(tester, [
      PatrimonioPoint(
        month: ReportMonth(2026, 9),
        realCostUsdCents: 5000,
        marketValueUsdCents: 4500,
      ),
    ]);

    expect(find.byType(LineChart), findsOneWidget);
  });

  testWidgets('shows an empty state with no points', (tester) async {
    await pump(tester, []);

    expect(find.byType(LineChart), findsNothing);
    expect(find.text('Sin datos de patrimonio'), findsOneWidget);
  });
}
