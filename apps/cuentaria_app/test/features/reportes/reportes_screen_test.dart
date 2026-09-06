import 'package:cuentaria_app/features/reportes/ui/screens/reportes_screen.dart';
import 'package:cuentaria_app/features/reportes/ui/screens/patrimonio_en_tiempo_screen.dart';
import 'package:cuentaria_app/features/reportes/ui/screens/rate_series_screen.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:cuentaria_app/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  final september6th2026 = DateTime(2026, 9, 6, 12);

  Future<void> pumpScreen(WidgetTester tester, {Brightness? brightness}) async {
    await tester.binding.setSurfaceSize(const Size(600, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      initialLocation: '/reports',
      routes: [
        GoRoute(
          path: '/reports',
          builder: (context, state) => ReportesScreen(now: september6th2026),
        ),
        GoRoute(
          path: '/reports/rate-series',
          builder: (context, state) => const RateSeriesScreen(),
        ),
        GoRoute(
          path: '/reports/patrimonio-en-el-tiempo',
          builder: (context, state) => const PatrimonioEnTiempoScreen(),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [isWebProvider.overrideWithValue(true)],
        child: MaterialApp.router(
          theme:
              brightness == Brightness.dark ? appDarkTheme() : appLightTheme(),
          routerConfig: router,
        ),
      ),
    );
  }

  testWidgets('opens on the current month with five empty sections, the '
      'live Patrimonio en el tiempo entry and the Serie de tasas entry', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text('Septiembre 2026'), findsOneWidget);

    const emptySections = [
      'Gasto por sobre',
      'Ingreso por fuente',
      'Diferencial cambiario',
      'Aportes a metas',
      'Deuda por persona',
    ];
    for (final title in emptySections) {
      expect(find.text(title), findsOneWidget);
    }
    expect(
      find.text('Aún no hay datos para este mes'),
      findsNWidgets(emptySections.length),
    );
    expect(find.text('Patrimonio en el tiempo'), findsOneWidget);
    expect(find.byKey(const Key('patrimonioEnTiempoEntry')), findsOneWidget);
    expect(find.text('Serie de tasas'), findsOneWidget);

    final nextButton = tester.widget<IconButton>(
      find.byKey(const Key('reportesNextMonthButton')),
    );
    expect(nextButton.onPressed, isNull);
  });

  testWidgets('← twice shows Julio 2026; → twice returns to Septiembre 2026 '
      'with the → arrow disabled again', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('reportesPreviousMonthButton')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('reportesPreviousMonthButton')));
    await tester.pump();

    expect(find.text('Julio 2026'), findsOneWidget);

    await tester.tap(find.byKey(const Key('reportesNextMonthButton')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('reportesNextMonthButton')));
    await tester.pump();

    expect(find.text('Septiembre 2026'), findsOneWidget);
    final nextButton = tester.widget<IconButton>(
      find.byKey(const Key('reportesNextMonthButton')),
    );
    expect(nextButton.onPressed, isNull);
  });

  testWidgets('dark theme renders section body text with a non-transparent, '
      'non-black-on-black color', (tester) async {
    await pumpScreen(tester, brightness: Brightness.dark);

    final bodyText = tester.widget<Text>(
      find.text('Aún no hay datos para este mes').first,
    );
    final color =
        bodyText.style?.color ??
        Theme.of(
          tester.element(find.text('Aún no hay datos para este mes').first),
        ).textTheme.bodyMedium?.color;

    expect(color, isNotNull);
    expect(color, isNot(Colors.black));
  });

  testWidgets('tapping Serie de tasas navigates to RateSeriesScreen', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('rateSeriesEntry')));
    await tester.pumpAndSettle();

    expect(find.byType(RateSeriesScreen), findsOneWidget);
  });

  testWidgets(
    'tapping Patrimonio en el tiempo navigates to PatrimonioEnTiempoScreen',
    (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('patrimonioEnTiempoEntry')));
      await tester.pumpAndSettle();

      expect(find.byType(PatrimonioEnTiempoScreen), findsOneWidget);
    },
  );
}
