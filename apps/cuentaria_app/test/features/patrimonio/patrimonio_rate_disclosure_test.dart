import 'package:cuentaria_app/features/patrimonio/application/patrimonio_providers.dart';
import 'package:cuentaria_app/features/patrimonio/ui/screens/patrimonio_screen.dart';
import 'package:cuentaria_app/providers/composition_root.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrimonio/patrimonio.dart';
import 'package:shared_kernel/shared_kernel.dart';

/// #176: Patrimonio must announce which rate valued its figures — value,
/// source and age, same format as the capture sheet's disclosure — per
/// ADR-0018 §4, instead of showing a silent number.
void main() {
  final ves = CurrencyCode('VES');

  Future<void> pumpWithGroup(
    WidgetTester tester,
    PatrimonioAccountGroup group,
  ) async {
    final container = ProviderContainer(
      overrides: [
        isWebProvider.overrideWithValue(true),
        patrimonioSnapshotProvider.overrideWith(
          (ref) async => PatrimonioSnapshot(
            realCostUsdCents: group.realCostUsdCents,
            todayValueUsdCents: group.todayValueUsdCents,
            unrealizedPnlUsdCents: 0,
            bcvReferenceUsdCents: group.bcvReferenceUsdCents,
            hasMissingRate: !group.hasRate,
            accountGroups: [group],
            envelopes: const [],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PatrimonioScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'shows the parallel rate used, with source and age, when observed today',
    (tester) async {
      final observedAt = DateTime.now().toUtc();
      await pumpWithGroup(
        tester,
        PatrimonioAccountGroup(
          currency: ves,
          nativeMinorAmount: BigInt.from(100000),
          realCostUsdCents: 1000,
          todayValueUsdCents: 1000,
          bcvReferenceUsdCents: 1000,
          hasRate: true,
          hasBcvRate: true,
          parallelRate: RateObservationView(
            nativePerUsd: Decimal.parse('846.50'),
            observedAt: observedAt,
            source: 'binancep2p:ask',
          ),
          bcvRate: RateObservationView(
            nativePerUsd: Decimal.parse('700.00'),
            observedAt: observedAt,
            source: 'dolarapi:oficial',
          ),
        ),
      );

      final parallelText =
          tester
              .widget<Text>(
                find.byKey(const Key('parallelRateAnnouncement_VES')),
              )
              .data!;
      expect(parallelText, contains('846.50'));
      expect(parallelText, contains('VES/USD'));
      expect(parallelText, contains('Binance P2P'));
    },
  );

  testWidgets('shows the BCV rate used to calculate the reference', (
    tester,
  ) async {
    final observedAt = DateTime.now().toUtc();
    await pumpWithGroup(
      tester,
      PatrimonioAccountGroup(
        currency: ves,
        nativeMinorAmount: BigInt.from(100000),
        realCostUsdCents: 1000,
        todayValueUsdCents: 1000,
        bcvReferenceUsdCents: 1000,
        hasRate: true,
        hasBcvRate: true,
        parallelRate: RateObservationView(
          nativePerUsd: Decimal.parse('846.50'),
          observedAt: observedAt,
          source: 'binancep2p:ask',
        ),
        bcvRate: RateObservationView(
          nativePerUsd: Decimal.parse('700.00'),
          observedAt: observedAt,
          source: 'dolarapi:oficial',
        ),
      ),
    );

    final bcvText =
        tester
            .widget<Text>(find.byKey(const Key('bcvRateAnnouncement_VES')))
            .data!;
    expect(bcvText, contains('700.00'));
    expect(bcvText, contains('DolarApi (oficial)'));
  });

  testWidgets(
    'shows the expired-rate warning without blocking when the parallel '
    'observation is not from today',
    (tester) async {
      final longAgo = DateTime.now().toUtc().subtract(const Duration(days: 5));
      await pumpWithGroup(
        tester,
        PatrimonioAccountGroup(
          currency: ves,
          nativeMinorAmount: BigInt.from(100000),
          realCostUsdCents: 1000,
          todayValueUsdCents: 1000,
          bcvReferenceUsdCents: 1000,
          hasRate: true,
          hasBcvRate: true,
          parallelRate: RateObservationView(
            nativePerUsd: Decimal.parse('846.50'),
            observedAt: longAgo,
            source: 'binancep2p:ask',
          ),
          bcvRate: RateObservationView(
            nativePerUsd: Decimal.parse('700.00'),
            observedAt: longAgo,
            source: 'dolarapi:oficial',
          ),
        ),
      );

      expect(find.byKey(const Key('parallelStaleWarning_VES')), findsOneWidget);
      // Non-blocking: the figures the group carries still render normally.
      expect(find.text('Costo real: \$10.00 · Hoy: \$10.00'), findsOneWidget);
    },
  );

  testWidgets(
    'declares a currency with no known rate instead of a silent number',
    (tester) async {
      await pumpWithGroup(
        tester,
        PatrimonioAccountGroup(
          currency: ves,
          nativeMinorAmount: BigInt.from(100000),
          realCostUsdCents: 1000,
          todayValueUsdCents: 1000,
          bcvReferenceUsdCents: 1000,
          hasRate: false,
          hasBcvRate: false,
        ),
      );

      expect(
        find.byKey(const Key('parallelRateUnavailable_VES')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('bcvRateUnavailable_VES')), findsOneWidget);
    },
  );

  testWidgets('USD groups need no rate disclosure — there is no conversion', (
    tester,
  ) async {
    await pumpWithGroup(
      tester,
      PatrimonioAccountGroup(
        currency: CurrencyCode('USD'),
        nativeMinorAmount: BigInt.from(1000),
        realCostUsdCents: 1000,
        todayValueUsdCents: 1000,
        bcvReferenceUsdCents: 1000,
        hasRate: true,
        hasBcvRate: true,
      ),
    );

    expect(find.textContaining('RateAnnouncement'), findsNothing);
    expect(find.byKey(const Key('parallelRateUnavailable_USD')), findsNothing);
  });
}
