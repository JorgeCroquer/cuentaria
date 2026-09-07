import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_kernel/shared_kernel.dart';

import '../../../../providers/tasas_providers.dart';
import '../widgets/rate_series_chart.dart';
import '../widgets/rate_series_latest_list.dart';

/// Serie de tasas (#261, ADR-0020 §"a territorio S5"): read-only history of
/// [RateSeries] observations by currency and source, reached from Reportes.
/// Selecting a source here is out of scope (ADR-0020 deferred it) — this
/// screen only shows what the Rate Resolution Chain already picks.
class RateSeriesScreen extends ConsumerStatefulWidget {
  const RateSeriesScreen({super.key});

  @override
  ConsumerState<RateSeriesScreen> createState() => _RateSeriesScreenState();
}

class _RateSeriesScreenState extends ConsumerState<RateSeriesScreen> {
  CurrencyCode? _selected;

  @override
  Widget build(BuildContext context) {
    final currenciesAsync = ref.watch(currenciesWithObservationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Serie de tasas')),
      body: currenciesAsync.when(
        data: (currencies) {
          if (currencies.isEmpty) {
            return const Center(child: Text('Sin observaciones de tasa'));
          }
          final selected =
              _selected != null && currencies.contains(_selected)
                  ? _selected!
                  : currencies.first;
          return _RateSeriesBody(
            currencies: currencies,
            selected: selected,
            onSelect: (currency) => setState(() => _selected = currency),
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

class _RateSeriesBody extends ConsumerWidget {
  const _RateSeriesBody({
    required this.currencies,
    required this.selected,
    required this.onSelect,
  });

  final List<CurrencyCode> currencies;
  final CurrencyCode selected;
  final ValueChanged<CurrencyCode> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final observationsAsync = ref.watch(
      rateSeriesObservationsProvider(selected),
    );
    final latestAsync = ref.watch(latestPerSourceProvider(selected));
    final resolutionAsync = ref.watch(latestParaleloRateProvider(selected));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButton<CurrencyCode>(
          key: const Key('rateSeriesCurrencySelector'),
          value: selected,
          items: [
            for (final currency in currencies)
              DropdownMenuItem(value: currency, child: Text(currency.value)),
          ],
          onChanged: (currency) {
            if (currency != null) onSelect(currency);
          },
        ),
        const SizedBox(height: 16),
        observationsAsync.when(
          data: (observations) => RateSeriesChart(observations: observations),
          loading: () => const Center(child: CircularProgressIndicator()),
          error:
              (error, stackTrace) =>
                  Center(child: Text('No se pudo cargar: $error')),
        ),
        const SizedBox(height: 16),
        latestAsync.when(
          data:
              (latest) => RateSeriesLatestList(
                latest: latest,
                resolvedSource: resolutionAsync.value?.source,
              ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error:
              (error, stackTrace) =>
                  Center(child: Text('No se pudo cargar: $error')),
        ),
      ],
    );
  }
}
