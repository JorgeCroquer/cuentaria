import 'package:flutter/material.dart';
import 'package:tasas/domain/rate_observation.dart';

/// Human-readable provenance for a source (#261) — like the `_sourceLabel`
/// helper duplicated in the account/patrimonio/capture forms, but this one
/// also distinguishes `binancep2p:bid` since the Serie de tasas shows both
/// sides of the Binance P2P book as separate lines/rows.
String _sourceLabel(String source) => switch (source) {
  'dolarapi:oficial' => 'DolarApi (oficial)',
  'dolarapi:paralelo' => 'DolarApi (paralelo)',
  'binancep2p:ask' => 'Binance P2P (venta)',
  'binancep2p:bid' => 'Binance P2P (compra)',
  _ => 'Manual',
};

String _formatDate(DateTime date) {
  final local = date.toLocal();
  final year = local.year.toString().padLeft(4, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

/// Latest observation per source for a currency (#261), with the one the
/// Rate Resolution Chain would pick today — [resolvedSource] — marked with
/// a checkmark, so the reader sees at a glance which figure prices the
/// ledger without opening the capture sheet.
class RateSeriesLatestList extends StatelessWidget {
  const RateSeriesLatestList({
    super.key,
    required this.latest,
    required this.resolvedSource,
  });

  final List<RateObservation> latest;
  final String? resolvedSource;

  @override
  Widget build(BuildContext context) {
    if (latest.isEmpty) {
      return const Center(child: Text('Sin observaciones de tasa'));
    }

    return Column(
      children: [
        for (final observation in latest)
          ListTile(
            key: Key('rateSeriesLatest_${observation.source}'),
            leading:
                observation.source == resolvedSource
                    ? const Icon(Icons.check_circle)
                    : null,
            title: Text(_sourceLabel(observation.source)),
            subtitle: Text(_formatDate(observation.observedAt)),
            trailing: Text(
              '${observation.nativePerUsd} ${observation.currency.value}',
            ),
          ),
      ],
    );
  }
}
