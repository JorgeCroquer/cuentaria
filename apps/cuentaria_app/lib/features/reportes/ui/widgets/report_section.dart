import 'package:flutter/material.dart';

/// One of the six Reportes sections (ADR-0024 §7), filled in future slices.
/// For now, just its empty state: es-VE text, no spinner and no empty
/// graphic per the S3 lesson that a skeleton screen ships text, not loaders.
class ReportSection extends StatelessWidget {
  const ReportSection({super.key, required this.slug, required this.title});

  final String slug;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: Key('reportSection_$slug'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Aún no hay datos para este mes',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
