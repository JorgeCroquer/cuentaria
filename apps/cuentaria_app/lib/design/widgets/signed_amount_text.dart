import 'package:flutter/material.dart';

/// The sign of a formatted amount, driving [SignedAmountText]'s color.
enum AmountSign { negative, positive, neutral }

/// A preformatted amount colored by [sign] — error/primary/onSurface, weight
/// 500 — the single place this color rule lives across the app.
class SignedAmountText extends StatelessWidget {
  const SignedAmountText({
    super.key,
    required this.amount,
    required this.sign,
    this.textKey,
  });

  final String amount;
  final AmountSign sign;

  /// Key placed on the rendered [Text] itself, for callers that need to
  /// locate the amount independently of this wrapper's own [key].
  final Key? textKey;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = switch (sign) {
      AmountSign.negative => colorScheme.error,
      AmountSign.positive => colorScheme.primary,
      AmountSign.neutral => colorScheme.onSurface,
    };
    return Text(
      amount,
      key: textKey,
      style: TextStyle(color: color, fontWeight: FontWeight.w500),
    );
  }
}
