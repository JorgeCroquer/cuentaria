import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';
import 'package:shared_kernel/shared_kernel.dart';

import 'rate_observation.dart';

/// Priority among same-calendar-day candidates (#165): a manual entry wins
/// because the user just transacted and knows the real number; among
/// automatics, Binance P2P is canonical because it is an **executable**
/// price, while an aggregator's parallel figure is a third-party average
/// (CONTEXT.md "Valor de Liquidación").
const _sourcePriority = <String>[
  'manual:paralelo',
  'binancep2p:ask',
  'dolarapi:paralelo',
];

/// The rate [resolve] picked to price a movement.
class Resolution extends Equatable {
  final Decimal nativePerUsd;
  final String source;
  final DateTime observedAt;

  Resolution({
    required this.nativePerUsd,
    required this.source,
    required this.observedAt,
  });

  @override
  List<Object?> get props => [nativePerUsd, source, observedAt];
}

/// The Rate Resolution Chain (#165, ADR-0020 §4): picks which of
/// [candidates] prices a movement for [currency] as of [asOf].
///
/// The most recent calendar day wins outright; [_sourcePriority] only
/// breaks a tie among candidates observed on that same day — so a manual
/// entry prices the day it was typed but never hijacks the days after it.
/// Candidates from another currency, observed after [asOf], or from a
/// source outside the chain (e.g. `manual:bcv`, `dolarapi:oficial`) are
/// never picked. Returns `null` when nothing is eligible. Pure, no I/O:
/// sister of the Reconciliation Planner (ADR-0019 §C3-8).
Resolution? resolve(
  CurrencyCode currency,
  DateTime asOf,
  List<RateObservation> candidates,
) {
  RateObservation? winner;
  for (final candidate in candidates) {
    if (candidate.currency != currency) continue;
    if (candidate.observedAt.isAfter(asOf)) continue;
    if (!_sourcePriority.contains(candidate.source)) continue;
    if (winner == null || _beats(candidate, winner)) {
      winner = candidate;
    }
  }
  if (winner == null) return null;

  return Resolution(
    nativePerUsd: winner.nativePerUsd,
    source: winner.source,
    observedAt: winner.observedAt,
  );
}

bool _beats(RateObservation candidate, RateObservation current) {
  final dayCompare = _calendarDay(
    candidate.observedAt,
  ).compareTo(_calendarDay(current.observedAt));
  if (dayCompare != 0) return dayCompare > 0;
  return _sourcePriority.indexOf(candidate.source) <
      _sourcePriority.indexOf(current.source);
}

DateTime _calendarDay(DateTime observedAt) {
  final utc = observedAt.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}
