import 'package:cuentaria_app/design/widgets.dart';
import 'package:cuentaria_app/providers/visibility_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<ColorScheme> pump(WidgetTester tester, Widget child) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(balancesHiddenProvider.notifier).show();
    late ColorScheme colorScheme;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              colorScheme = Theme.of(context).colorScheme;
              return Scaffold(body: child);
            },
          ),
        ),
      ),
    );
    return colorScheme;
  }

  testWidgets('negative amount paints colorScheme.error at weight 500', (
    tester,
  ) async {
    final colorScheme = await pump(
      tester,
      const SignedAmountText(amount: '-\$5.00', sign: AmountSign.negative),
    );

    final text = tester.widget<Text>(find.text('-\$5.00'));
    expect(text.style?.color, colorScheme.error);
    expect(text.style?.fontWeight, FontWeight.w500);
  });

  testWidgets('positive amount paints colorScheme.primary at weight 500', (
    tester,
  ) async {
    final colorScheme = await pump(
      tester,
      const SignedAmountText(amount: '\$5.00', sign: AmountSign.positive),
    );

    final text = tester.widget<Text>(find.text('\$5.00'));
    expect(text.style?.color, colorScheme.primary);
    expect(text.style?.fontWeight, FontWeight.w500);
  });

  testWidgets('neutral amount paints colorScheme.onSurface at weight 500', (
    tester,
  ) async {
    final colorScheme = await pump(
      tester,
      const SignedAmountText(amount: '\$0.00', sign: AmountSign.neutral),
    );

    final text = tester.widget<Text>(find.text('\$0.00'));
    expect(text.style?.color, colorScheme.onSurface);
    expect(text.style?.fontWeight, FontWeight.w500);
  });

  testWidgets('textKey lands on the rendered Text for callers to find '
      'their amount by key', (tester) async {
    await pump(
      tester,
      const SignedAmountText(
        textKey: Key('pnlAmount'),
        amount: '\$5.00',
        sign: AmountSign.positive,
      ),
    );

    expect(
      tester.widget<Text>(find.byKey(const Key('pnlAmount'))).data,
      '\$5.00',
    );
  });

  testWidgets('masks the amount when balances are hidden (#333)', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(balancesHiddenProvider.notifier).hide();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SignedAmountText(
              textKey: Key('pnlAmount'),
              amount: '\$5.00',
              sign: AmountSign.positive,
            ),
          ),
        ),
      ),
    );

    expect(
      tester.widget<Text>(find.byKey(const Key('pnlAmount'))).data,
      '\$••••',
    );
  });
}
