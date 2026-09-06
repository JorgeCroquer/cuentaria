import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:reportes/reportes.dart';

import '../widgets/income_by_source_section.dart';
import '../widgets/month_selector.dart';
import '../widgets/report_section.dart';
import '../widgets/spending_by_envelope_section.dart';

class _SectionSpec {
  const _SectionSpec(this.slug, this.title);

  final String slug;
  final String title;
}

/// Order fixed by ADR-0024 §7: Gasto · Ingreso · Patrimonio · Diferencial ·
/// Aportes · Deuda. Gasto por sobre (#259) and Ingreso por fuente (#262) are
/// now live; the rest stay placeholders until the slices that follow this
/// skeleton fill them in.
const _placeholderSections = [
  _SectionSpec('patrimonioEnElTiempo', 'Patrimonio en el tiempo'),
  _SectionSpec('diferencialCambiario', 'Diferencial cambiario'),
  _SectionSpec('aportesAMetas', 'Aportes a metas'),
  _SectionSpec('deudaPorPersona', 'Deuda por persona'),
];

/// Reportes screen (S3/S5, #258, ADR-0024): nace with its full navigation
/// and skeleton — month selector plus the six report sections, each an
/// empty state until the slices that follow fill them in. The month is the
/// screen's only shared state; [MonthCalendar] (the `reportes` engine) is
/// the single place that cuts a UTC instant into a [ReportMonth], so a
/// late-night expense never lands in the wrong month just because it's
/// stored in UTC.
class ReportesScreen extends StatefulWidget {
  const ReportesScreen({super.key, this.now});

  /// Overridable for tests; defaults to [DateTime.now()] in production.
  final DateTime? now;

  @override
  State<ReportesScreen> createState() => _ReportesScreenState();
}

class _ReportesScreenState extends State<ReportesScreen> {
  late final ReportMonth _currentMonth;
  late ReportMonth _selectedMonth;

  @override
  void initState() {
    super.initState();
    final now = widget.now ?? DateTime.now();
    _currentMonth = MonthCalendar.getReportMonth(
      now.toUtc(),
      now.timeZoneOffset,
    );
    _selectedMonth = _currentMonth;
  }

  bool get _canGoForward => _selectedMonth != _currentMonth;

  void _goToPreviousMonth() {
    setState(() => _selectedMonth = _selectedMonth.previousMonth);
  }

  void _goToNextMonth() {
    setState(() => _selectedMonth = _selectedMonth.nextMonth);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reportes')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          MonthSelector(
            month: _selectedMonth,
            canGoForward: _canGoForward,
            onPrevious: _goToPreviousMonth,
            onNext: _goToNextMonth,
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SpendingByEnvelopeSection(month: _selectedMonth),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: IncomeBySourceSection(month: _selectedMonth),
          ),
          for (final section in _placeholderSections)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child:
                  section.slug == 'patrimonioEnElTiempo'
                      ? _PatrimonioEnTiempoEntry(title: section.title)
                      : ReportSection(slug: section.slug, title: section.title),
            ),
          Card(
            key: const Key('rateSeriesEntry'),
            child: ListTile(
              title: const Text('Serie de tasas'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/reports/rate-series'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Live entry point for Patrimonio en el tiempo (#260), replacing the
/// generic [ReportSection] empty state now that the section is implemented
/// — same navigable-card pattern as the Serie de tasas entry (#261).
class _PatrimonioEnTiempoEntry extends StatelessWidget {
  const _PatrimonioEnTiempoEntry({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('patrimonioEnTiempoEntry'),
      child: ListTile(
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/reports/patrimonio-en-el-tiempo'),
      ),
    );
  }
}
