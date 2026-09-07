import 'package:flutter/material.dart';

import 'signed_amount_text.dart';

/// A chronological group header: an uppercase [label] on the left and a
/// signed amount on the right.
class DayGroupHeader extends StatelessWidget {
  const DayGroupHeader({
    super.key,
    required this.label,
    required this.amount,
    required this.sign,
    this.amountKey,
  });

  final String label;
  final String amount;
  final AmountSign sign;
  final Key? amountKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const Spacer(),
        SignedAmountText(textKey: amountKey, amount: amount, sign: sign),
      ],
    );
  }
}
