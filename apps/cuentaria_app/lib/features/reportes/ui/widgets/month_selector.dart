import 'package:flutter/material.dart';
import 'package:reportes/reportes.dart';

const _monthNames = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

/// Lowercase Spanish name of a calendar [month] (1-12), shared with any
/// widget that needs to name a [ReportMonth] in prose (e.g. "vs julio").
String monthName(int month) => _monthNames[month - 1];

String _monthLabel(ReportMonth month) {
  final name = monthName(month.month);
  return '${name[0].toUpperCase()}${name.substring(1)} ${month.year}';
}

/// The Reportes screen's only shared state (ADR-0024 §7): month name and
/// year, ← → to navigate, never past the current month.
class MonthSelector extends StatelessWidget {
  const MonthSelector({
    super.key,
    required this.month,
    required this.canGoForward,
    required this.onPrevious,
    required this.onNext,
  });

  final ReportMonth month;
  final bool canGoForward;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          key: const Key('reportesPreviousMonthButton'),
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Mes anterior',
          onPressed: onPrevious,
        ),
        Text(
          _monthLabel(month),
          key: const Key('reportesMonthLabel'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        IconButton(
          key: const Key('reportesNextMonthButton'),
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Mes siguiente',
          onPressed: canGoForward ? onNext : null,
        ),
      ],
    );
  }
}
