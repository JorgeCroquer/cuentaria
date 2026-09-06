import 'package:cuentaria_app/features/reportes/application/spending_by_envelope_providers.dart';
import 'package:cuentaria_app/features/reportes/ui/widgets/spending_by_envelope_section.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reportes/reportes.dart';
import 'package:shared_kernel/shared_kernel.dart';

void main() {
  final august = ReportMonth(2026, 8);
  final comida = EnvelopeId('comida');
  final transporte = EnvelopeId('transporte');
  final ajustesId = EnvelopeId('ajustes');
  final diferencialId = EnvelopeId('diferencial');

  Future<void> pump(
    WidgetTester tester,
    SpendingByEnvelopeResult result,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          spendingByEnvelopeProvider(
            august,
          ).overrideWith((ref) async => result),
        ],
        child: MaterialApp(
          home: Scaffold(body: SpendingByEnvelopeSection(month: august)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the empty state text when there is no spending', (
    tester,
  ) async {
    await pump(
      tester,
      const SpendingByEnvelopeResult(
        rows: [],
        adjustments: null,
        differential: null,
        totalUsdCents: 0,
      ),
    );

    expect(find.text('Gasto por sobre'), findsOneWidget);
    expect(find.text('Aún no hay datos para este mes'), findsOneWidget);
    expect(find.byType(BarChart), findsNothing);
  });

  testWidgets(
    'renders the total, a horizontal bar chart and one row per envelope, '
    'highest spend first',
    (tester) async {
      await pump(
        tester,
        SpendingByEnvelopeResult(
          rows: [
            SpendingRow(
              envelopeId: comida,
              label: 'Comida',
              amountUsdCents: 4000,
              previousAmountUsdCents: 0,
            ),
            SpendingRow(
              envelopeId: transporte,
              label: 'Transporte',
              amountUsdCents: 2500,
              previousAmountUsdCents: 0,
            ),
          ],
          adjustments: null,
          differential: null,
          totalUsdCents: 6500,
        ),
      );

      expect(find.textContaining('65.00'), findsOneWidget);
      expect(find.byType(BarChart), findsOneWidget);
      final chart = tester.widget<BarChart>(find.byType(BarChart));
      expect(chart.data.barGroups, hasLength(2));

      expect(find.textContaining('Comida'), findsOneWidget);
      expect(find.textContaining('Transporte'), findsOneWidget);
    },
  );

  testWidgets('shows the % change against the previous month', (tester) async {
    await pump(
      tester,
      SpendingByEnvelopeResult(
        rows: [
          SpendingRow(
            envelopeId: comida,
            label: 'Comida',
            amountUsdCents: 13000,
            previousAmountUsdCents: 10000,
          ),
        ],
        adjustments: null,
        differential: null,
        totalUsdCents: 13000,
      ),
    );

    expect(find.textContaining('+30'), findsOneWidget);
    expect(find.textContaining('julio'), findsOneWidget);
  });

  testWidgets('shows Ajustes and Diferencial realizado as their own rows, '
      'outside the chart', (tester) async {
    await pump(
      tester,
      SpendingByEnvelopeResult(
        rows: [],
        adjustments: SpendingRow(
          envelopeId: ajustesId,
          label: 'Ajustes',
          amountUsdCents: -60,
          previousAmountUsdCents: 0,
        ),
        differential: SpendingRow(
          envelopeId: diferencialId,
          label: 'Diferencial realizado',
          amountUsdCents: 1200,
          previousAmountUsdCents: 0,
        ),
        totalUsdCents: 0,
      ),
    );

    expect(find.textContaining('Ajustes'), findsOneWidget);
    expect(find.textContaining('Diferencial realizado'), findsOneWidget);
    expect(find.byType(BarChart), findsNothing);
  });
}
