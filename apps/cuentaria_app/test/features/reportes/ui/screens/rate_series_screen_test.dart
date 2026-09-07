import 'package:cuentaria_app/features/reportes/ui/screens/rate_series_screen.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:cuentaria_app/providers/tasas_providers.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/domain/rate_observation.dart';

RateObservation _obs({
  required String currency,
  required String rate,
  required DateTime observedAt,
  required String source,
}) => RateObservation(
  currency: CurrencyCode(currency),
  nativePerUsd: Decimal.parse(rate),
  observedAt: observedAt,
  source: source,
);

Future<ProviderContainer> _seededContainer(
  List<RateObservation> observations,
) async {
  final container = ProviderContainer(
    overrides: [isWebProvider.overrideWithValue(true)],
  );
  final series = await container.read(rateSeriesProvider.future);
  for (final observation in observations) {
    await series.append(observation);
  }
  return container;
}

void main() {
  testWidgets(
    'with three VES sources, selector defaults to VES, the chart and list '
    'render, and the manual rate registered today is marked as resolving',
    (tester) async {
      final today = DateTime.utc(2026, 9, 6);
      final container = await _seededContainer([
        _obs(
          currency: 'VES',
          rate: '845',
          observedAt: today.subtract(const Duration(days: 1)),
          source: 'binancep2p:ask',
        ),
        _obs(
          currency: 'VES',
          rate: '840',
          observedAt: today.subtract(const Duration(days: 1)),
          source: 'dolarapi:paralelo',
        ),
        _obs(
          currency: 'VES',
          rate: '900',
          observedAt: today,
          source: 'manual:paralelo',
        ),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: RateSeriesScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('rateSeriesCurrencySelector')),
        findsOneWidget,
      );
      final dropdown = tester.widget<DropdownButton<CurrencyCode>>(
        find.byKey(const Key('rateSeriesCurrencySelector')),
      );
      expect(dropdown.value, CurrencyCode('VES'));

      expect(
        find.byKey(const Key('rateSeriesLatest_manual:paralelo')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('rateSeriesLatest_binancep2p:ask')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('rateSeriesLatest_dolarapi:paralelo')),
        findsOneWidget,
      );

      final markedTile = tester.widget<ListTile>(
        find.byKey(const Key('rateSeriesLatest_manual:paralelo')),
      );
      expect(markedTile.leading, isA<Icon>());
    },
  );

  testWidgets('a currency with no observations never appears in the selector', (
    tester,
  ) async {
    final container = await _seededContainer([
      _obs(
        currency: 'VES',
        rate: '900',
        observedAt: DateTime.utc(2026, 9, 6),
        source: 'manual:paralelo',
      ),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: RateSeriesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final dropdown = tester.widget<DropdownButton<CurrencyCode>>(
      find.byKey(const Key('rateSeriesCurrencySelector')),
    );
    final offeredCurrencies =
        dropdown.items!.map((item) => item.value).toList();
    expect(offeredCurrencies, [CurrencyCode('VES')]);
    expect(offeredCurrencies, isNot(contains(CurrencyCode('EUR'))));
  });

  testWidgets('shows an empty state when no currency has any observation', (
    tester,
  ) async {
    final container = await _seededContainer([]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: RateSeriesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('rateSeriesCurrencySelector')), findsNothing);
    expect(find.text('Sin observaciones de tasa'), findsOneWidget);
  });

  testWidgets('selecting a different currency switches the chart and list '
      'to that currency\'s observations', (tester) async {
    final container = await _seededContainer([
      _obs(
        currency: 'VES',
        rate: '900',
        observedAt: DateTime.utc(2026, 9, 6),
        source: 'manual:paralelo',
      ),
      _obs(
        currency: 'EUR',
        rate: '38',
        observedAt: DateTime.utc(2026, 9, 6),
        source: 'manual:paralelo',
      ),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: RateSeriesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('rateSeriesCurrencySelector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('EUR').last);
    await tester.pumpAndSettle();

    final dropdown = tester.widget<DropdownButton<CurrencyCode>>(
      find.byKey(const Key('rateSeriesCurrencySelector')),
    );
    expect(dropdown.value, CurrencyCode('EUR'));
    expect(find.text('38 EUR'), findsOneWidget);
  });
}
