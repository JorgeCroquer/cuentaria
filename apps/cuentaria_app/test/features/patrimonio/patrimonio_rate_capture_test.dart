import 'package:cuentaria_app/features/patrimonio/ui/screens/patrimonio_screen.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:cuentaria_app/providers/tasas_providers.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_kernel/shared_kernel.dart';

void main() {
  testWidgets(
    'recording BCV and parallel rates from the Patrimonio header appends '
    'both observations',
    (tester) async {
      final container = ProviderContainer(
        overrides: [isWebProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: PatrimonioScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('recordRatesAction')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('bcvRateField')), '37.5');
      await tester.enterText(find.byKey(const Key('paraleloRateField')), '90');
      await tester.tap(find.byKey(const Key('saveRatesButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('bcvRateField')), findsNothing);

      final series = await container.read(rateSeriesProvider.future);
      final latest = await series.latestFor(CurrencyCode('VES'));
      expect(latest, isNotNull);
      expect(latest!.source, 'manual:paralelo');
      expect(latest.nativePerUsd, Decimal.parse('90'));
    },
  );
}
