import 'package:cuentaria_app/features/reportes/application/patrimonio_en_tiempo_providers.dart';
import 'package:cuentaria_app/features/reportes/ui/screens/patrimonio_en_tiempo_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reportes/reportes.dart';

final _points = [
  PatrimonioPoint(
    month: ReportMonth(2026, 7),
    realCostUsdCents: 10000,
    marketValueUsdCents: 9500,
    rateSource: 'manual:paralelo',
    rateObservedAt: DateTime(2026, 4, 15),
  ),
  PatrimonioPoint(
    month: ReportMonth(2026, 8),
    realCostUsdCents: 11000,
    marketValueUsdCents: null,
  ),
  PatrimonioPoint(
    month: ReportMonth(2026, 9),
    realCostUsdCents: 12000,
    marketValueUsdCents: 11500,
    rateSource: 'dolarapi:paralelo',
    rateObservedAt: DateTime(2026, 9, 6),
  ),
];

Future<void> _pumpScreen(
  WidgetTester tester,
  List<PatrimonioPoint> points,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        patrimonioEnTiempoPointsProvider.overrideWith((ref) async => points),
      ],
      child: const MaterialApp(home: PatrimonioEnTiempoScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'opens on the latest month, showing both figures and the rate note',
    (tester) async {
      await _pumpScreen(tester, _points);

      expect(find.text('Septiembre 2026'), findsOneWidget);
      expect(find.text('Costo real: \$120.00'), findsOneWidget);
      expect(find.text('Valor de mercado: \$115.00'), findsOneWidget);
      expect(find.text('DolarApi, tasa del 06/09'), findsOneWidget);
    },
  );

  testWidgets('← moves to the previous month, showing a blank overlay when the '
      'point has no market value', (tester) async {
    await _pumpScreen(tester, _points);

    await tester.tap(
      find.byKey(const Key('patrimonioEnTiempoPreviousMonthButton')),
    );
    await tester.pump();

    expect(find.text('Agosto 2026'), findsOneWidget);
    expect(find.text('Costo real: \$110.00'), findsOneWidget);
    expect(find.text('Valor de mercado: sin tasa disponible'), findsOneWidget);
    expect(find.byKey(const Key('patrimonioEnTiempoRateNote')), findsNothing);
  });

  testWidgets('the ← arrow disables at the first month', (tester) async {
    await _pumpScreen(tester, _points);

    await tester.tap(
      find.byKey(const Key('patrimonioEnTiempoPreviousMonthButton')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('patrimonioEnTiempoPreviousMonthButton')),
    );
    await tester.pump();

    expect(find.text('Julio 2026'), findsOneWidget);
    final previousButton = tester.widget<IconButton>(
      find.byKey(const Key('patrimonioEnTiempoPreviousMonthButton')),
    );
    expect(previousButton.onPressed, isNull);
    expect(find.text('manual, tasa del 15/04'), findsOneWidget);
  });

  testWidgets('a single month of history renders one point without crashing', (
    tester,
  ) async {
    await _pumpScreen(tester, [
      PatrimonioPoint(
        month: ReportMonth(2026, 9),
        realCostUsdCents: 5000,
        marketValueUsdCents: 4500,
      ),
    ]);

    expect(find.text('Septiembre 2026'), findsOneWidget);
    final previousButton = tester.widget<IconButton>(
      find.byKey(const Key('patrimonioEnTiempoPreviousMonthButton')),
    );
    final nextButton = tester.widget<IconButton>(
      find.byKey(const Key('patrimonioEnTiempoNextMonthButton')),
    );
    expect(previousButton.onPressed, isNull);
    expect(nextButton.onPressed, isNull);
  });
}
