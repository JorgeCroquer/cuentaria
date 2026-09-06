import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reportes/reportes.dart';

import '../../application/exchange_differential_providers.dart';
import 'exchange_differential_chart.dart';

String _formatSignedUsdCents(int cents) {
  final sign = cents < 0 ? '-' : '+';
  return '$sign\$${(cents.abs() / 100).toStringAsFixed(2)}';
}

/// Diferencial cambiario (ADR-0024, #264): realizado (#259's Sobre de
/// Sistema Diferencial flow) and no realizado (#260's market-value-minus-
/// real-cost overlay gap) shown together, always both, signed and colored —
/// green for a gain, red (the app's existing error color) for a loss — plus
/// the last 12 months as a bar-and-line chart. Wired to
/// [exchangeDifferentialProvider], reactive the same way every other
/// EventBus-driven Reportes section is.
class ExchangeDifferentialSection extends ConsumerWidget {
  const ExchangeDifferentialSection({super.key, required this.month});

  final ReportMonth month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pointsAsync = ref.watch(exchangeDifferentialProvider(month));

    return Card(
      key: const Key('reportSection_diferencialCambiario'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Diferencial cambiario',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            pointsAsync.when(
              data: (points) {
                if (points.isEmpty) {
                  return const Text('Aún no hay datos para este mes');
                }
                return _ExchangeDifferentialBody(points: points);
              },
              loading:
                  () => const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              error: (error, stackTrace) => Text('No se pudo cargar: $error'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExchangeDifferentialBody extends StatelessWidget {
  const _ExchangeDifferentialBody({required this.points});

  final List<ExchangeDifferentialPoint> points;

  @override
  Widget build(BuildContext context) {
    final current = points.last;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _amountRow(
          context,
          key: const Key('exchangeDifferentialRealizado'),
          label: 'Realizado',
          amountUsdCents: current.realizadoUsdCents,
        ),
        const SizedBox(height: 4),
        if (current.noRealizadoUsdCents case final noRealizado?)
          _amountRow(
            context,
            key: const Key('exchangeDifferentialNoRealizado'),
            label: 'No realizado',
            amountUsdCents: noRealizado,
          )
        else
          const Text(
            'No realizado: sin tasa disponible',
            key: Key('exchangeDifferentialNoRealizadoBlank'),
          ),
        const SizedBox(height: 12),
        ExchangeDifferentialChart(points: points),
      ],
    );
  }
}

/// A label/amount row — [key] lands on the amount [Text] itself, the piece
/// tests and screenshots care about, not on the [Row] wrapper.
Widget _amountRow(
  BuildContext context, {
  required Key key,
  required String label,
  required int amountUsdCents,
}) {
  final color =
      amountUsdCents < 0 ? Theme.of(context).colorScheme.error : Colors.green;

  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label),
      Text(
        _formatSignedUsdCents(amountUsdCents),
        key: key,
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    ],
  );
}
