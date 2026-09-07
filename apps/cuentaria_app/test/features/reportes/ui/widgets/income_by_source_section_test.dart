import 'package:cuentaria_app/features/reportes/application/income_by_source_providers.dart';
import 'package:cuentaria_app/features/reportes/ui/widgets/income_by_source_section.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reportes/reportes.dart';

void main() {
  final august = ReportMonth(2026, 8);

  Future<void> pump(WidgetTester tester, IncomeBySourceResult result) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          incomeBySourceProvider(august).overrideWith((ref) async => result),
        ],
        child: MaterialApp(
          home: Scaffold(body: IncomeBySourceSection(month: august)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the empty state text when there is no income', (
    tester,
  ) async {
    await pump(tester, const IncomeBySourceResult(rows: [], totalUsdCents: 0));

    expect(find.text('Ingreso por fuente'), findsOneWidget);
    expect(find.text('Aún no hay datos para este mes'), findsOneWidget);
    expect(find.byType(BarChart), findsNothing);
  });

  testWidgets(
    'renders the total, a horizontal bar chart and one row per source, '
    'highest income first',
    (tester) async {
      await pump(
        tester,
        const IncomeBySourceResult(
          rows: [
            IncomeRow(
              label: 'Acme',
              amountUsdCents: 50000,
              previousAmountUsdCents: 0,
            ),
            IncomeRow(
              label: 'Sin fuente',
              amountUsdCents: 15000,
              previousAmountUsdCents: 0,
            ),
          ],
          totalUsdCents: 65000,
        ),
      );

      expect(find.textContaining('650.00'), findsOneWidget);
      expect(find.byType(BarChart), findsOneWidget);
      final chart = tester.widget<BarChart>(find.byType(BarChart));
      expect(chart.data.barGroups, hasLength(2));

      expect(find.textContaining('Acme'), findsOneWidget);
      expect(find.textContaining('Sin fuente'), findsOneWidget);
    },
  );

  testWidgets('shows the % change against the previous month', (tester) async {
    await pump(
      tester,
      const IncomeBySourceResult(
        rows: [
          IncomeRow(
            label: 'Acme',
            amountUsdCents: 50000,
            previousAmountUsdCents: 40000,
          ),
        ],
        totalUsdCents: 50000,
      ),
    );

    expect(find.textContaining('+25'), findsOneWidget);
    expect(find.textContaining('julio'), findsOneWidget);
  });
}
