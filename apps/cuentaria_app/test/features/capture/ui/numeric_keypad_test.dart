import 'package:cuentaria_app/features/capture/ui/amount_input_controller.dart';
import 'package:cuentaria_app/features/capture/ui/widgets/numeric_keypad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<AmountInputController> pumpKeypad(WidgetTester tester) async {
    final controller = AmountInputController();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: NumericKeypad(controller: controller))),
    );
    return controller;
  }

  testWidgets('renders the 10 digit buttons and a backspace button', (
    tester,
  ) async {
    await pumpKeypad(tester);

    for (var digit = 0; digit <= 9; digit++) {
      expect(find.byKey(Key('keypadDigit_$digit')), findsOneWidget);
    }
    expect(find.byKey(const Key('keypadBackspace')), findsOneWidget);
  });

  testWidgets('tapping digits appends them to the controller', (tester) async {
    final controller = await pumpKeypad(tester);

    await tester.tap(find.byKey(const Key('keypadDigit_1')));
    await tester.tap(find.byKey(const Key('keypadDigit_2')));
    await tester.pump();

    expect(controller.displayText, '0.12');
  });

  testWidgets('tapping backspace removes the last digit', (tester) async {
    final controller = await pumpKeypad(tester);

    await tester.tap(find.byKey(const Key('keypadDigit_1')));
    await tester.tap(find.byKey(const Key('keypadDigit_2')));
    await tester.tap(find.byKey(const Key('keypadBackspace')));
    await tester.pump();

    expect(controller.displayText, '0.01');
  });
}
