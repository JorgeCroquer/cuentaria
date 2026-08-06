/// Drift-backed implementation of [RateSeries].
///
///   - [append]: plain insert — the series is append-only, no conflict
///     resolution needed (ADR-0002).
///   - [latestFor]: orders by `observed_at DESC, id DESC` so a tie on
///     [RateObservation.observedAt] resolves to the last row appended.
library;

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:shared_kernel/shared_kernel.dart';

import '../../domain/rate_observation.dart';
import '../../domain/rate_series.dart';
import 'tasas_database.dart';

class DriftRateSeries implements RateSeries {
  final TasasDatabase _db;

  DriftRateSeries(this._db);

  @override
  Future<void> append(RateObservation observation) async {
    await _db
        .into(_db.rateObservations)
        .insert(
          RateObservationsCompanion.insert(
            currency: observation.currency.value,
            nativePerUsd: observation.nativePerUsd.toString(),
            observedAt: observation.observedAt.microsecondsSinceEpoch,
            source: observation.source,
          ),
        );
  }

  @override
  Future<RateObservation?> latestFor(
    CurrencyCode currency, {
    String? source,
    DateTime? asOf,
  }) async {
    final row =
        await (_db.select(_db.rateObservations)
              ..where(
                (t) =>
                    t.currency.equals(currency.value) &
                    (source == null
                        ? const Constant(true)
                        : t.source.equals(source)) &
                    (asOf == null
                        ? const Constant(true)
                        : t.observedAt.isSmallerOrEqualValue(
                          asOf.microsecondsSinceEpoch,
                        )),
              )
              ..orderBy([
                (t) => OrderingTerm.desc(t.observedAt),
                (t) => OrderingTerm.desc(t.id),
              ])
              ..limit(1))
            .getSingleOrNull();

    if (row == null) return null;
    return RateObservation(
      currency: CurrencyCode(row.currency),
      nativePerUsd: Decimal.parse(row.nativePerUsd),
      observedAt: DateTime.fromMicrosecondsSinceEpoch(
        row.observedAt,
        isUtc: true,
      ),
      source: row.source,
    );
  }

  @override
  Future<List<RateObservation>> candidatesFor(
    CurrencyCode currency, {
    DateTime? asOf,
  }) async {
    final rows =
        await (_db.select(_db.rateObservations)
              ..where(
                (t) =>
                    t.currency.equals(currency.value) &
                    (asOf == null
                        ? const Constant(true)
                        : t.observedAt.isSmallerOrEqualValue(
                          asOf.microsecondsSinceEpoch,
                        )),
              )
              ..orderBy([
                (t) => OrderingTerm.desc(t.observedAt),
                (t) => OrderingTerm.desc(t.id),
              ]))
            .get();

    final seenSources = <String>{};
    final candidates = <RateObservation>[];
    for (final row in rows) {
      if (!seenSources.add(row.source)) continue;
      candidates.add(
        RateObservation(
          currency: CurrencyCode(row.currency),
          nativePerUsd: Decimal.parse(row.nativePerUsd),
          observedAt: DateTime.fromMicrosecondsSinceEpoch(
            row.observedAt,
            isUtc: true,
          ),
          source: row.source,
        ),
      );
    }
    return candidates;
  }
}
