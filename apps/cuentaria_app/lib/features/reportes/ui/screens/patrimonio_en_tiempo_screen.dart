import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reportes/reportes.dart';

import '../../application/patrimonio_en_tiempo_providers.dart';
import '../widgets/patrimonio_en_tiempo_chart.dart';

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
/// Patrimonio hoy's disclosure (ADR-0018 §4).
String _sourceLabel(String source) => switch (source) {
  'dolarapi:oficial' => 'DolarApi (oficial)',
  'binancep2p:ask' => 'Binance P2P',
  'dolarapi:paralelo' => 'DolarApi',
  _ => 'manual',
};

/// Patrimonio en el tiempo (#260, ADR-0024 §5-6): twelve Net Worth Points,
/// one per month-end, plotted as real cost (frozen, ADR-0006) and market
/// value. The month navigator below the chart selects which point's detail
/// is shown — it never fetches a different range, it only moves the cursor
/// over [patrimonioEnTiempoPointsProvider]'s fixed 12 points.
class PatrimonioEnTiempoScreen extends ConsumerStatefulWidget {
  const PatrimonioEnTiempoScreen({super.key});

  @override
  ConsumerState<PatrimonioEnTiempoScreen> createState() =>
      _PatrimonioEnTiempoScreenState();
}

class _PatrimonioEnTiempoScreenState
    extends ConsumerState<PatrimonioEnTiempoScreen> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    final pointsAsync = ref.watch(patrimonioEnTiempoPointsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Patrimonio en el tiempo')),
      body: pointsAsync.when(
        data: (points) {
          if (points.isEmpty) {
            return const Center(child: Text('Sin datos de patrimonio'));
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

  final List<PatrimonioPoint> points;
  final int selectedIndex;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final selected = points[selectedIndex];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        PatrimonioEnTiempoChart(points: points),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              key: const Key('patrimonioEnTiempoPreviousMonthButton'),
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Mes anterior',
              onPressed: onPrevious,
            ),
            Text(
              _monthLabel(selected.month),
              key: const Key('patrimonioEnTiempoSelectedMonthLabel'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            IconButton(
              key: const Key('patrimonioEnTiempoNextMonthButton'),
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Mes siguiente',
              onPressed: onNext,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Costo real: ${_formatUsdCents(selected.realCostUsdCents)}',
          key: const Key('patrimonioEnTiempoRealCost'),
        ),
        const SizedBox(height: 8),
        if (selected.marketValueUsdCents case final marketValue?)
          Text(
            'Valor de mercado: ${_formatUsdCents(marketValue)}',
            key: const Key('patrimonioEnTiempoMarketValue'),
          )
        else
          const Text(
            'Valor de mercado: sin tasa disponible',
            key: Key('patrimonioEnTiempoMarketValueBlank'),
          ),
        if (selected.rateSource != null && selected.rateObservedAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${_sourceLabel(selected.rateSource!)}, '
              'tasa del ${_formatRateDate(selected.rateObservedAt!)}',
              key: const Key('patrimonioEnTiempoRateNote'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}
