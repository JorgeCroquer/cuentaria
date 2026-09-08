import 'package:cuentaria_app/design/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the label and a signed amount', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DayGroupHeader(
            label: '7 SEP',
            amount: '-\$12.00',
            sign: AmountSign.negative,
            amountKey: Key('dayAmount'),
          ),
        ),
      ),
    );

    expect(find.text('7 SEP'), findsOneWidget);
    final amountText = tester.widget<Text>(find.byKey(const Key('dayAmount')));
    final context = tester.element(find.byKey(const Key('dayAmount')));
    expect(amountText.data, '-\$12.00');
    expect(amountText.style?.color, Theme.of(context).colorScheme.error);
  });
}
