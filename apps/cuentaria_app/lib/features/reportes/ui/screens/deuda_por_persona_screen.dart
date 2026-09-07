import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reportes/reportes.dart';

import '../../application/deudas_en_tiempo_providers.dart';
import '../widgets/deuda_por_persona_chart.dart';

String _formatUsdCents(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';

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

String _monthLabel(ReportMonth month) {
  final name = _monthNames[month.month - 1];
  return '${name[0].toUpperCase()}${name.substring(1)} ${month.year}';
}

String _formatRateDate(DateTime date) {
  final local = date.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  return '$day/$month';
}

/// Human-readable provenance for the rate a point used, same convention as
/// Patrimonio en el tiempo's disclosure (ADR-0018 §4).
String _sourceLabel(String source) => switch (source) {
  'dolarapi:oficial' => 'DolarApi (oficial)',
  'binancep2p:ask' => 'Binance P2P',
  'dolarapi:paralelo' => 'DolarApi',
  _ => 'manual',
};

/// Sign spoken in the user's language, same wording as the Deudas screen's
/// `_PersonTile` headline (#207/#265).
String _headline(PersonDebtPoint persona) =>
    persona.netoUsdCents >= 0
        ? '${persona.personName} te debe '
            '${_formatUsdCents(persona.netoUsdCents)}'
        : 'le debés ${_formatUsdCents(-persona.netoUsdCents)} a '
            '${persona.personName}';

/// Deuda por persona en el tiempo (#265): twelve Debt Points, one per
/// month-end, plotted as one line per counterparty. The month navigator
/// below the chart selects which point's detail list is shown — it never
/// fetches a different range, it only moves the cursor over
/// [debtsEnTiempoPointsProvider]'s fixed 12 points, same pattern as
/// [PatrimonioEnTiempoScreen].
class DeudaPorPersonaScreen extends ConsumerStatefulWidget {
  const DeudaPorPersonaScreen({super.key});

  @override
  ConsumerState<DeudaPorPersonaScreen> createState() =>
      _DeudaPorPersonaScreenState();
}

class _DeudaPorPersonaScreenState extends ConsumerState<DeudaPorPersonaScreen> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    final pointsAsync = ref.watch(debtsEnTiempoPointsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Deuda por persona')),
      body: pointsAsync.when(
        data: (points) {
          if (points.isEmpty) {
            return const Center(child: Text('Sin datos de deudas'));
          }
          final index = (_selectedIndex ?? points.length - 1).clamp(
            0,
            points.length - 1,
          );
          return _Body(
            points: points,
            selectedIndex: index,
            onPrevious:
                index > 0
                    ? () => setState(() => _selectedIndex = index - 1)
                    : null,
            onNext:
                index < points.length - 1
                    ? () => setState(() => _selectedIndex = index + 1)
                    : null,
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error:
            (error, stackTrace) =>
                Center(child: Text('No se pudo cargar: $error')),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.points,
    required this.selectedIndex,
    required this.onPrevious,
    required this.onNext,
  });

  final List<DebtPoint> points;
  final int selectedIndex;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final selected = points[selectedIndex];
    final hasAnyDebt = points.any((point) => point.personas.isNotEmpty);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (hasAnyDebt) DeudaPorPersonaChart(points: points),
        if (hasAnyDebt) const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              key: const Key('deudaPorPersonaPreviousMonthButton'),
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Mes anterior',
              onPressed: onPrevious,
            ),
            Text(
              _monthLabel(selected.month),
              key: const Key('deudaPorPersonaSelectedMonthLabel'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            IconButton(
              key: const Key('deudaPorPersonaNextMonthButton'),
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Mes siguiente',
              onPressed: onNext,
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (selected.personas.isEmpty)
          const Text(
            'Sin deudas ese mes',
            key: Key('deudaPorPersonaEmptyMonth'),
          )
        else
          for (final persona in selected.personas)
            Padding(
              key: Key('deudaPorPersonaRow_${persona.personName}'),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(_headline(persona)),
            ),
        if (selected.rateSource != null && selected.rateObservedAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${_sourceLabel(selected.rateSource!)}, '
              'tasa del ${_formatRateDate(selected.rateObservedAt!)}',
              key: const Key('deudaPorPersonaRateNote'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}
