import 'package:flutter/material.dart';

import '../amount_input_controller.dart';

/// Amount-first digit pad for quick-add capture (U1 slice 4, #97):
/// 0–9 shift new digits in from the right, backspace removes the last one.
/// No decimal key — the split between whole units and cents is purely
/// display formatting, driven by [AmountInputController].
class NumericKeypad extends StatelessWidget {
  const NumericKeypad({
    required this.controller,
    this.onDonePressed,
    super.key,
  });

  final AmountInputController controller;

  /// Confirms the typed amount (#158): when provided, replaces the keypad's
  /// otherwise-blank corner with a "Listo" key. Callers that evaluate the
  /// amount on every digit (none left after #158) don't need to pass it.
  final VoidCallback? onDonePressed;

  static const _layout = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['', '0', '⌫'],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('numericKeypad'),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in _layout)
          Row(
            children: [
              for (final label in row)
                Expanded(child: _buildKey(context, label)),
            ],
          ),
      ],
    );
  }

  Widget _buildKey(BuildContext context, String label) {
    if (label.isEmpty) {
      final onDonePressed = this.onDonePressed;
      if (onDonePressed == null) return const SizedBox.shrink();
      return TextButton(
        key: const Key('keypadDone'),
        onPressed: onDonePressed,
        child: Text('Listo', style: Theme.of(context).textTheme.headlineSmall),
      );
    }

    if (label == '⌫') {
      return IconButton(
        key: const Key('keypadBackspace'),
        icon: const Icon(Icons.backspace_outlined),
        onPressed: controller.backspace,
      );
    }

    return TextButton(
      key: Key('keypadDigit_$label'),
      onPressed: () => controller.appendDigit(label),
      child: Text(label, style: Theme.of(context).textTheme.headlineSmall),
    );
  }
}
