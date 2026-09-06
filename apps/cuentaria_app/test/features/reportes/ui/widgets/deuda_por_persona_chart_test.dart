import 'package:cuentaria_app/features/reportes/ui/widgets/deuda_por_persona_chart.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reportes/reportes.dart';

void main() {
  Future<void> pump(WidgetTester tester, List<DebtPoint> points) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: DeudaPorPersonaChart(points: points))),
    );
  }

  testWidgets(
    'renders one line per person, with a gap where they had no balance',
    (tester) async {
      await pump(tester, [
        DebtPoint(
          month: ReportMonth(2026, 7),
          personas: const [
            PersonDebtPoint(personName: 'Pedro', netoUsdCents: 20000),
          ],
        ),
        DebtPoint(
          month: ReportMonth(2026, 8),
          personas: const [
            PersonDebtPoint(personName: 'Pedro', netoUsdCents: 15000),
            PersonDebtPoint(personName: 'Ana', netoUsdCents: -5000),
          ],
        ),
        DebtPoint(
          month: ReportMonth(2026, 9),
          personas: const [
            PersonDebtPoint(personName: 'Pedro', netoUsdCents: 15000),
          ],
        ),
      ]);

      final chart = tester.widget<LineChart>(find.byType(LineChart));
      expect(chart.data.lineBarsData, hasLength(2));

      final ana = chart.data.lineBarsData[0];
      expect(ana.spots[0], FlSpot.nullSpot);
      expect(ana.spots[1].y, -50.0);
      expect(ana.spots[2], FlSpot.nullSpot);

      final pedro = chart.data.lineBarsData[1];
      expect(pedro.spots.map((s) => s.y), [200.0, 150.0, 150.0]);
    },
  );

  testWidgets('a single point renders without crashing', (tester) async {
    await pump(tester, [
      DebtPoint(
        month: ReportMonth(2026, 9),
        personas: const [
          PersonDebtPoint(personName: 'Pedro', netoUsdCents: 20000),
        ],
      ),
    ]);

    expect(find.byType(LineChart), findsOneWidget);
  });

  testWidgets('shows an empty state with no points', (tester) async {
    await pump(tester, []);

    expect(find.byType(LineChart), findsNothing);
    expect(find.text('Sin datos de deudas'), findsOneWidget);
  });
}
