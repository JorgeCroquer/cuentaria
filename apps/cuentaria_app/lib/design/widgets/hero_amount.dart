import 'package:flutter/material.dart';

import '../../ui/theme/app_theme.dart';

/// The protagonist figure of a dashboard: a top label, a big number, and an
/// optional secondary line (typically a signed amount).
class HeroAmount extends StatelessWidget {
  const HeroAmount({
    super.key,
    required this.label,
    required this.amount,
    this.amountKey,
    this.secondaryLine,
  });

  final String label;
  final String amount;
  final Key? amountKey;
  final Widget? secondaryLine;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(amount, key: amountKey, style: textTheme.displaySmall),
        if (secondaryLine != null) ...[
          const SizedBox(height: AppSpacing.sm),
          secondaryLine!,
        ],
      ],
    );
  }
}
