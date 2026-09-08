import 'package:flutter/material.dart';

import '../../ui/theme/app_theme.dart';

/// A [Card] with an uppercase [header] and a list of [children], optionally
/// separated by internal dividers.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.header,
    required this.children,
    this.headerKey,
    this.showDividers = false,
  });

  final String header;
  final List<Widget> children;
  final Key? headerKey;
  final bool showDividers;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (showDividers && i > 0) rows.add(const Divider(height: 1));
      rows.add(children[i]);
    }

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xs,
            ),
            child: Text(
              header,
              key: headerKey,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          ...rows,
        ],
      ),
    );
  }
}
