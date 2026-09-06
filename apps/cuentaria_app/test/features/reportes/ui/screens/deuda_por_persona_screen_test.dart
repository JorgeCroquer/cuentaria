import 'package:cuentaria_app/features/reportes/application/deudas_en_tiempo_providers.dart';
import 'package:cuentaria_app/features/reportes/ui/screens/deuda_por_persona_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reportes/reportes.dart';

final _points = [
  DebtPoint(
    month: ReportMonth(2026, 7),
    personas: const [PersonDebtPoint(personName: 'Pedro', netoUsdCents: 20000)],
  ),
  DebtPoint(
    month: ReportMonth(2026, 8),
    personas: const [
      PersonDebtPoint(personName: 'Pedro', netoUsdCents: 15000),
      PersonDebtPoint(personName: 'Ana', netoUsdCents: -4000),
    ],
    rateSource: 'dolarapi:paralelo',
    rateObservedAt: DateTime.utc(2026, 8, 31),
  ),
  DebtPoint(
    month: ReportMonth(2026, 9),
    personas: const [PersonDebtPoint(personName: 'Pedro', netoUsdCents: 15000)],
  ),
];

Future<void> _pumpScreen(WidgetTester tester, List<DebtPoint> points) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        debtsEnTiempoPointsProvider.overrideWith((ref) async => points),
      ],
      child: const MaterialApp(home: DeudaPorPersonaScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens on the latest month, showing that month\'s balances', (
    tester,
  ) async {
    await _pumpScreen(tester, _points);

    expect(find.text('Septiembre 2026'), findsOneWidget);
    expect(find.text('Pedro te debe \$150.00'), findsOneWidget);
  });

  testWidgets(
    '← moves to the previous month, showing every persona and the rate note',
    (tester) async {
      await _pumpScreen(tester, _points);

      await tester.tap(
        find.byKey(const Key('deudaPorPersonaPreviousMonthButton')),
      );
      await tester.pump();

      expect(find.text('Agosto 2026'), findsOneWidget);
      expect(find.text('Pedro te debe \$150.00'), findsOneWidget);
      expect(find.text('le debés \$40.00 a Ana'), findsOneWidget);
      expect(find.text('DolarApi, tasa del 31/08'), findsOneWidget);
    },
  );

  testWidgets('the ← arrow disables at the first month', (tester) async {
    await _pumpScreen(tester, _points);

    await tester.tap(
      find.byKey(const Key('deudaPorPersonaPreviousMonthButton')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('deudaPorPersonaPreviousMonthButton')),
    );
    await tester.pump();

    expect(find.text('Julio 2026'), findsOneWidget);
    final previousButton = tester.widget<IconButton>(
      find.byKey(const Key('deudaPorPersonaPreviousMonthButton')),
    );
    expect(previousButton.onPressed, isNull);
  });

  testWidgets('shows an empty state with no Debt Accounts at all', (
    tester,
  ) async {
    await _pumpScreen(tester, [
      DebtPoint(month: ReportMonth(2026, 9), personas: const []),
    ]);

    expect(find.text('Sin deudas ese mes'), findsOneWidget);
  });
}
