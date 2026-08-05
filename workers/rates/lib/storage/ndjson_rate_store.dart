import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:shared_kernel/shared_kernel.dart';
import 'package:tasas/domain/rate_observation.dart';

/// The append-only NDJSON feed published as a GitHub Release asset
/// (ADR-0020 §1): one observation per line, deduped by
/// `(currency, source, observedAt)` so a re-published feed never reorders
/// or repeats a line already out there.
class NdjsonRateStore {
  final List<RateObservation> _observations = [];
  final Set<String> _keys = {};

  NdjsonRateStore._();

  factory NdjsonRateStore.parse(String ndjson) {
    final store = NdjsonRateStore._();
    for (final line in ndjson.split('\n')) {
      if (line.trim().isEmpty) continue;
      store.append(_decode(line));
    }
    return store;
  }

  List<RateObservation> get observations => List.unmodifiable(_observations);

  /// Appends [observation] unless a previous line already reported the same
  /// `(currency, source, observedAt)`. Returns whether it was added.
  bool append(RateObservation observation) {
    final key = _keyOf(observation);
    if (!_keys.add(key)) return false;
    _observations.add(observation);
    return true;
  }

  String serialize() => _observations.map(_encode).join('\n');

  static String _keyOf(RateObservation observation) =>
      '${observation.currency.value}|${observation.source}|'
      '${observation.observedAt.toUtc().toIso8601String()}';

  static String _encode(RateObservation observation) => jsonEncode({
    'currency': observation.currency.value,
    'source': observation.source,
    'nativePerUsd': observation.nativePerUsd.toString(),
    'observedAt': observation.observedAt.toUtc().toIso8601String(),
  });

  static RateObservation _decode(String line) {
    final map = jsonDecode(line) as Map<String, dynamic>;
    return RateObservation(
      currency: CurrencyCode(map['currency'] as String),
      source: map['source'] as String,
      nativePerUsd: Decimal.parse(map['nativePerUsd'] as String),
      observedAt: DateTime.parse(map['observedAt'] as String),
    );
  }
}
