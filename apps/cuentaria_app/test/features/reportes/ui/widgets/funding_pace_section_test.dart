import 'package:cuentaria_app/features/reportes/application/funding_pace_providers.dart';
import 'package:cuentaria_app/features/reportes/ui/widgets/funding_pace_section.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reportes/reportes.dart';
import 'package:shared_kernel/shared_kernel.dart';

void main() {
  final august = ReportMonth(2026, 8);
  final viaje = EnvelopeId('viaje');

  Future<void> pump(
    WidgetTester tester,
    FundingPaceSectionResult result,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fundingPaceProvider(august).overrideWith((ref) async => result),
        ],
        child: MaterialApp(
          home: Scaffold(body: FundingPaceSection(month: august)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the empty state text when no envelope has a goal', (
    tester,
  ) async {
    await pump(tester, const FundingPaceSectionResult(rows: []));

    expect(find.text('Aportes a metas'), findsOneWidget);
    expect(find.text('Aún no hay datos para este mes'), findsOneWidget);
    expect(find.byType(BarChart), findsNothing);
  });

  testWidgets(
    'renders the aporte, required per month and status, plus the 12-month '
    'bar chart',
    (tester) async {
      await pump(
        tester,
        FundingPaceSectionResult(
          rows: [
            FundingPaceEnvelopeResult(
              row: FundingPaceRow(
                envelopeId: viaje,
                name: 'Viaje',
                contributedThisMonthUsdCents: 25000,
                requiredPerMonthUsdCents: 20000,
                status: FundingPaceStatus.onPace,
              ),
              monthlyContributionsUsdCents: List.filled(11, 0) + [25000],
            ),
          ],
        ),
      );

      expect(find.textContaining('Viaje'), findsOneWidget);
      expect(find.textContaining('250.00'), findsOneWidget);
      expect(find.textContaining('200.00'), findsOneWidget);
      expect(find.textContaining('al ritmo'), findsOneWidget);
      expect(find.byType(BarChart), findsOneWidget);
      final chart = tester.widget<BarChart>(find.byType(BarChart));
      expect(chart.data.barGroups, hasLength(12));
    },
  );

  testWidgets('shows only the aportado, with no status, when there is no '
      'due date', (tester) async {
    await pump(
      tester,
      FundingPaceSectionResult(
        rows: [
          FundingPaceEnvelopeResult(
            row: FundingPaceRow(
              envelopeId: viaje,
              name: 'Viaje',
              contributedThisMonthUsdCents: 25000,
              requiredPerMonthUsdCents: null,
              status: null,
            ),
            monthlyContributionsUsdCents: List.filled(12, 0),
          ),
        ],
      ),
    );

    expect(find.textContaining('250.00'), findsOneWidget);
    expect(find.textContaining('necesitás'), findsNothing);
  });

  testWidgets('shows meta alcanzada when the goal is already reached', (
    tester,
  ) async {
    await pump(
      tester,
      FundingPaceSectionResult(
        rows: [
          FundingPaceEnvelopeResult(
            row: FundingPaceRow(
              envelopeId: viaje,
              name: 'Viaje',
              contributedThisMonthUsdCents: 0,
              requiredPerMonthUsdCents: 0,
              status: FundingPaceStatus.goalReached,
            ),
            monthlyContributionsUsdCents: List.filled(12, 0),
          ),
        ],
      ),
    );

    expect(find.textContaining('meta alcanzada'), findsOneWidget);
  });
}
