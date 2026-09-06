import 'package:cuentaria_app/features/reportes/application/exchange_differential_providers.dart';
import 'package:cuentaria_app/features/reportes/ui/widgets/exchange_differential_section.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reportes/reportes.dart';

void main() {
  final august = ReportMonth(2026, 8);

  List<ExchangeDifferentialPoint> pointsEndingAt(
    ExchangeDifferentialPoint last,
  ) {
    final points = <ExchangeDifferentialPoint>[];
    var month = last.month;
    for (var i = 0; i < 11; i++) {
      points.insert(
        0,
        ExchangeDifferentialPoint(month: month, realizadoUsdCents: 0),
      );
      month = month.previousMonth;
    }
    points.add(last);
    return points;
  }

  Future<void> pump(
    WidgetTester tester,
    List<ExchangeDifferentialPoint> points,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          exchangeDifferentialProvider(
            august,
          ).overrideWith((ref) async => points),
        ],
        child: MaterialApp(
          home: Scaffold(body: ExchangeDifferentialSection(month: august)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows realizado and no realizado in green when both are gains', (
    tester,
  ) async {
    await pump(
      tester,
      pointsEndingAt(
        ExchangeDifferentialPoint(
          month: august,
          realizadoUsdCents: 900,
          noRealizadoUsdCents: 8000,
        ),
      ),
    );

    expect(find.text('Diferencial cambiario'), findsOneWidget);
    final realizado = tester.widget<Text>(
      find.byKey(const Key('exchangeDifferentialRealizado')),
    );
    expect(realizado.data, contains('+\$9.00'));
    expect(realizado.style?.color, Colors.green);

    final noRealizado = tester.widget<Text>(
      find.byKey(const Key('exchangeDifferentialNoRealizado')),
    );
    expect(noRealizado.data, contains('+\$80.00'));
    expect(noRealizado.style?.color, Colors.green);

    expect(find.byType(BarChart), findsOneWidget);
    expect(find.byType(LineChart), findsOneWidget);
    final chart = tester.widget<BarChart>(find.byType(BarChart));
    expect(chart.data.barGroups, hasLength(12));
  });

  testWidgets('shows a loss in red for both realizado and no realizado', (
    tester,
  ) async {
    await pump(
      tester,
      pointsEndingAt(
        ExchangeDifferentialPoint(
          month: august,
          realizadoUsdCents: -300,
          noRealizadoUsdCents: -1500,
        ),
      ),
    );

    final realizado = tester.widget<Text>(
      find.byKey(const Key('exchangeDifferentialRealizado')),
    );
    expect(realizado.data, contains('-\$3.00'));
    expect(
      realizado.style?.color,
      Theme.of(
        tester.element(find.byType(ExchangeDifferentialSection)),
      ).colorScheme.error,
    );

    final noRealizado = tester.widget<Text>(
      find.byKey(const Key('exchangeDifferentialNoRealizado')),
    );
    expect(noRealizado.data, contains('-\$15.00'));
  });

  testWidgets('shows no realizado blank when the month has no rate', (
    tester,
  ) async {
    await pump(
      tester,
      pointsEndingAt(
        ExchangeDifferentialPoint(month: august, realizadoUsdCents: 0),
      ),
    );

    expect(
      find.byKey(const Key('exchangeDifferentialNoRealizadoBlank')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('exchangeDifferentialNoRealizado')),
      findsNothing,
    );
  });
}
