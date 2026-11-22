import 'package:cuentaria_app/features/reportes/application/deudas_en_tiempo_providers.dart';
import 'package:cuentaria_app/features/reportes/application/exchange_differential_providers.dart';
import 'package:cuentaria_app/features/reportes/application/funding_pace_providers.dart';
import 'package:cuentaria_app/features/reportes/application/income_by_source_providers.dart';
import 'package:cuentaria_app/features/reportes/application/patrimonio_en_tiempo_providers.dart';
import 'package:cuentaria_app/features/reportes/application/spending_by_envelope_providers.dart';
import 'package:cuentaria_app/features/reportes/ui/screens/deuda_por_persona_screen.dart';
import 'package:cuentaria_app/features/reportes/ui/screens/patrimonio_en_tiempo_screen.dart';
import 'package:cuentaria_app/features/reportes/ui/widgets/exchange_differential_section.dart';
import 'package:cuentaria_app/features/reportes/ui/widgets/funding_pace_section.dart';
import 'package:cuentaria_app/features/reportes/ui/widgets/income_by_source_section.dart';
import 'package:cuentaria_app/features/reportes/ui/widgets/spending_by_envelope_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reportes/reportes.dart';
import 'package:shared_kernel/shared_kernel.dart';

/// #333: balances hidden by default means Reportes' figures show no digit
/// either — totals, row amounts, headlines, and the money-value chart axis
/// (the lines/bars themselves still render).
void main() {
  final august = ReportMonth(2026, 8);

  bool noDigits(Iterable<String> texts) =>
      !texts.any((t) => RegExp(r'\d').hasMatch(t));

  testWidgets('spending by envelope: total and row amounts (#333)', (
    tester,
  ) async {
    final envelopeId = EnvelopeId('comida');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          spendingByEnvelopeProvider(august).overrideWith(
            (ref) async => SpendingByEnvelopeResult(
              totalUsdCents: 15000,
              adjustments: null,
              differential: null,
              rows: [
                SpendingRow(
                  envelopeId: envelopeId,
                  label: 'Comida',
                  amountUsdCents: 15000,
                  previousAmountUsdCents: 0,
                ),
              ],
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: SpendingByEnvelopeSection(month: august)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '');
    expect(noDigits(texts), isTrue);
  });

  testWidgets('income by source: total and row amounts (#333)', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          incomeBySourceProvider(august).overrideWith(
            (ref) async => const IncomeBySourceResult(
              totalUsdCents: 20000,
              rows: [
                IncomeRow(
                  label: 'Cliente X',
                  amountUsdCents: 20000,
                  previousAmountUsdCents: 0,
                ),
              ],
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: IncomeBySourceSection(month: august)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '');
    expect(noDigits(texts), isTrue);
  });

  testWidgets('funding pace: aportado/necesitás summary (#333)', (
    tester,
  ) async {
    final viaje = EnvelopeId('viaje');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fundingPaceProvider(august).overrideWith(
            (ref) async => FundingPaceSectionResult(
              rows: [
                FundingPaceEnvelopeResult(
                  row: FundingPaceRow(
                    envelopeId: viaje,
                    name: 'Viaje',
                    contributedThisMonthUsdCents: 5000,
                    requiredPerMonthUsdCents: 10000,
                    status: FundingPaceStatus.behind,
                  ),
                  monthlyContributionsUsdCents: List.filled(12, 5000),
                ),
              ],
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: FundingPaceSection(month: august)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '');
    expect(noDigits(texts), isTrue);
  });

  testWidgets('exchange differential: realizado/no realizado rows (#333)', (
    tester,
  ) async {
    var month = august;
    final points = <ExchangeDifferentialPoint>[];
    for (var i = 0; i < 11; i++) {
      points.insert(
        0,
        ExchangeDifferentialPoint(month: month, realizadoUsdCents: 0),
      );
      month = month.previousMonth;
    }
    points.add(
      ExchangeDifferentialPoint(
        month: august,
        realizadoUsdCents: 1200,
        noRealizadoUsdCents: -300,
      ),
    );

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

    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '');
    expect(noDigits(texts), isTrue);
  });

  testWidgets(
    'patrimonio en el tiempo: Costo real/Valor de mercado and chart axis '
    '(#333)',
    (tester) async {
      final points = [
        PatrimonioPoint(
          month: august,
          realCostUsdCents: 10000,
          marketValueUsdCents: 9500,
        ),
      ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            patrimonioEnTiempoPointsProvider.overrideWith(
              (ref) async => points,
            ),
          ],
          child: const MaterialApp(home: PatrimonioEnTiempoScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final realCost =
          tester
              .widget<Text>(find.byKey(const Key('patrimonioEnTiempoRealCost')))
              .data!;
      final marketValue =
          tester
              .widget<Text>(
                find.byKey(const Key('patrimonioEnTiempoMarketValue')),
              )
              .data!;
      expect(noDigits([realCost, marketValue]), isTrue);
    },
  );

  testWidgets('deuda por persona: headline (#333)', (tester) async {
    final points = [
      DebtPoint(
        month: august,
        personas: const [
          PersonDebtPoint(personName: 'Pedro', netoUsdCents: 20000),
        ],
      ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          debtsEnTiempoPointsProvider.overrideWith((ref) async => points),
        ],
        child: const MaterialApp(home: DeudaPorPersonaScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final headline =
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const Key('deudaPorPersonaRow_Pedro')),
                matching: find.byType(Text),
              ),
            )
            .data!;
    expect(noDigits([headline]), isTrue);
  });
}
