import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';
import 'package:shared_kernel/shared_kernel.dart';

import 'rate_observation.dart';

/// Priority among same-calendar-day candidates (#165): a manual entry wins
/// because the user just transacted and knows the real number; among
/// automatics, Binance P2P is canonical because it is an **executable**
/// price, while an aggregator's parallel figure is a third-party average
/// (CONTEXT.md "Valor de Liquidación"). Default [resolve] priority.
const _paraleloSourcePriority = <String>[
  'manual:paralelo',
  'binancep2p:ask',
  'dolarapi:paralelo',
];

/// Priority for the BCV/"oficial" series (#166): the published
/// `dolarapi:oficial` reading is preferred; `manual:bcv` only wins a
/// same-day tie — or is picked at all — when no automatic reading exists,
/// since BCV is an informational reference the user rarely has reason to
/// type by hand. Pass to [resolve]'s `sourcePriority` to resolve this
/// series instead of the default parallel one.
const oficialSourcePriority = <String>['dolarapi:oficial', 'manual:bcv'];

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
/// The most recent calendar day wins outright; [sourcePriority] only
/// breaks a tie among candidates observed on that same day — so a manual
/// entry prices the day it was typed but never hijacks the days after it.
/// Candidates from another currency, observed after [asOf], or from a
/// source outside [sourcePriority] (e.g. `manual:bcv`, `dolarapi:oficial`
/// when resolving the default parallel series) are never picked. Returns
/// `null` when nothing is eligible. Pure, no I/O: sister of the
/// Reconciliation Planner (ADR-0019 §C3-8).
///
/// [sourcePriority] defaults to the parallel chain; pass
/// [oficialSourcePriority] to resolve the BCV series instead (#166) — same
/// rule, different candidate list.
Resolution? resolve(
  CurrencyCode currency,
  DateTime asOf,
  List<RateObservation> candidates, {
  List<String> sourcePriority = _paraleloSourcePriority,
}) {
  RateObservation? winner;
  for (final candidate in candidates) {
    if (candidate.currency != currency) continue;
    if (candidate.observedAt.isAfter(asOf)) continue;
    if (!sourcePriority.contains(candidate.source)) continue;
    if (winner == null || _beats(candidate, winner, sourcePriority)) {
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

bool _beats(
  RateObservation candidate,
  RateObservation current,
  List<String> sourcePriority,
) {
  final dayCompare = _calendarDay(
    candidate.observedAt,
  ).compareTo(_calendarDay(current.observedAt));
  if (dayCompare != 0) return dayCompare > 0;
  return sourcePriority.indexOf(candidate.source) <
      sourcePriority.indexOf(current.source);
}

DateTime _calendarDay(DateTime observedAt) {
  final utc = observedAt.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}
