import 'package:cuentaria_app/features/reportes/ui/widgets/rate_series_latest_list.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/domain/rate_observation.dart';

RateObservation _obs({
  required String rate,
  required DateTime observedAt,
  required String source,
}) => RateObservation(
  currency: CurrencyCode('VES'),
  nativePerUsd: Decimal.parse(rate),
  observedAt: observedAt,
  source: source,
);

void main() {
  testWidgets(
    'renders one row per source, marking the one the Resolution Chain '
    'would pick today',
    (tester) async {
      final manual = _obs(
        rate: '900',
        observedAt: DateTime.utc(2026, 9, 6),
        source: 'manual:paralelo',
      );
      final ask = _obs(
        rate: '845',
        observedAt: DateTime.utc(2026, 9, 5),
        source: 'binancep2p:ask',
      );
      final paralelo = _obs(
        rate: '840',
        observedAt: DateTime.utc(2026, 9, 4),
        source: 'dolarapi:paralelo',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RateSeriesLatestList(
              latest: [manual, ask, paralelo],
              resolvedSource: 'manual:paralelo',
            ),
          ),
        ),
      );

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

      final unmarkedTile = tester.widget<ListTile>(
        find.byKey(const Key('rateSeriesLatest_binancep2p:ask')),
      );
      expect(unmarkedTile.leading, isNull);
    },
  );

  testWidgets('shows an empty state when there are no observations', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RateSeriesLatestList(latest: [], resolvedSource: null),
        ),
      ),
    );

    expect(find.text('Sin observaciones de tasa'), findsOneWidget);
  });
}
