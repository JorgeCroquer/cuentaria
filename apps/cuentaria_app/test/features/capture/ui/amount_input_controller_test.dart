import 'package:cuentaria_app/features/capture/ui/amount_input_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AmountInputController', () {
    test('starts empty and invalid', () {
      final controller = AmountInputController();
      expect(controller.displayText, '0.00');
      expect(controller.isValid, isFalse);
    });

    test('appending digits shifts them in as cents, right to left', () {
      final controller = AmountInputController();
      controller.appendDigit('1');
      controller.appendDigit('2');
      controller.appendDigit('3');
      controller.appendDigit('4');

      expect(controller.displayText, '12.34');
      expect(controller.amountMinorUnits, BigInt.from(1234));
      expect(controller.isValid, isTrue);
    });

    test('backspace removes the last digit', () {
      final controller = AmountInputController();
      controller.appendDigit('1');
      controller.appendDigit('2');
      controller.appendDigit('3');
      controller.backspace();

      expect(controller.displayText, '0.12');
    });

    test('backspace on an empty amount stays at zero and invalid', () {
      final controller = AmountInputController();
      controller.backspace();

      expect(controller.displayText, '0.00');
      expect(controller.isValid, isFalse);
    });

    test('an amount of exactly zero is invalid', () {
      final controller = AmountInputController();
      controller.appendDigit('0');
      controller.appendDigit('0');

      expect(controller.isValid, isFalse);
    });

    test('clear resets to zero', () {
      final controller = AmountInputController();
      controller.appendDigit('5');
      controller.clear();

      expect(controller.displayText, '0.00');
      expect(controller.isValid, isFalse);
    });
  });
}
