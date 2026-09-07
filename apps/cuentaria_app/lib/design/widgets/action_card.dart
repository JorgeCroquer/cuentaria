import 'package:flutter/material.dart';

import '../../ui/theme/app_theme.dart';

/// A tonal `secondaryContainer` card: an optional [title] and tappable
/// [subline], plus an optional [FilledButton] on the right.
class ActionCard extends StatelessWidget {
  const ActionCard({
    super.key,
    this.title,
    this.titleKey,
    this.subline,
    this.sublineKey,
    this.onSublineTap,
    this.buttonLabel,
    this.buttonKey,
    this.onButtonPressed,
  });

  final String? title;
  final Key? titleKey;
  final String? subline;
  final Key? sublineKey;
  final VoidCallback? onSublineTap;
  final String? buttonLabel;
  final Key? buttonKey;
  final VoidCallback? onButtonPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final onContainer = colorScheme.onSecondaryContainer;
    final textTheme = Theme.of(context).textTheme;
    final title = this.title;
    final subline = this.subline;
    final buttonLabel = this.buttonLabel;

    return Card(
      color: colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title != null)
                    Text(
                      title,
                      key: titleKey,
                      style: textTheme.titleMedium?.copyWith(
                        color: onContainer,
                      ),
                    ),
                  if (subline != null)
                    InkWell(
                      key: sublineKey,
                      onTap: onSublineTap,
                      child: Text(
                        subline,
                        style: textTheme.bodySmall?.copyWith(
                          color: onContainer,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (buttonLabel != null) ...[
              const SizedBox(width: AppSpacing.md),
              FilledButton(
                key: buttonKey,
                onPressed: onButtonPressed,
                child: Text(buttonLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
