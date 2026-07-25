import 'package:flutter/foundation.dart';

/// Buffers the digits typed on the [NumericKeypad] as minor units (cents),
/// shifted in from the right like a calculator tape — no decimal key needed,
/// matching how [Money] already represents amounts everywhere else.
class AmountInputController extends ChangeNotifier {
  String _digits = '';

  String get displayText {
    final padded = _digits.padLeft(3, '0');
    final wholeUnits = padded.substring(0, padded.length - 2);
    final cents = padded.substring(padded.length - 2);
    return '$wholeUnits.$cents';
  }

  BigInt get amountMinorUnits =>
      _digits.isEmpty ? BigInt.zero : BigInt.parse(_digits);

  bool get isValid => amountMinorUnits > BigInt.zero;

  void appendDigit(String digit) {
    _digits += digit;
    notifyListeners();
  }

  void backspace() {
    if (_digits.isEmpty) return;
    _digits = _digits.substring(0, _digits.length - 1);
    notifyListeners();
  }

  void clear() {
    _digits = '';
    notifyListeners();
  }
}
