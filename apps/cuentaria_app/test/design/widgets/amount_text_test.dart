import 'package:cuentaria_app/design/widgets.dart';
import 'package:cuentaria_app/providers/visibility_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('maskAmount', () {
    test('replaces the numeric run, keeping currency and position', () {
      expect(maskAmount('\$1,234.56'), '\$••••');
      expect(maskAmount('1,234.56 USD'), '•••• USD');
      expect(maskAmount('-\$5.00'), '-\$••••');
      expect(maskAmount('+\$5.00'), '+\$••••');
    });
  });

  group('AmountText', () {
    Future<void> pump(
      WidgetTester tester,
      Widget child, {
      required bool hidden,
    }) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      if (hidden) {
        container.read(balancesHiddenProvider.notifier).hide();
      } else {
        container.read(balancesHiddenProvider.notifier).show();
      }
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: Scaffold(body: child)),
        ),
      );
    }

    testWidgets('renders the plain amount when balances are visible', (
      tester,
    ) async {
      await pump(tester, const AmountText('\$1,234.56'), hidden: false);

      expect(find.text('\$1,234.56'), findsOneWidget);
    });

    testWidgets('renders the masked amount when balances are hidden', (
      tester,
    ) async {
      await pump(tester, const AmountText('\$1,234.56'), hidden: true);

      expect(find.text('\$1,234.56'), findsNothing);
      expect(find.text('\$••••'), findsOneWidget);
    });

    testWidgets('amountKey lands on the rendered Text', (tester) async {
      await pump(
        tester,
        const AmountText('\$1,234.56', amountKey: Key('amt')),
        hidden: true,
      );

      expect(tester.widget<Text>(find.byKey(const Key('amt'))).data, '\$••••');
    });
  });
}
