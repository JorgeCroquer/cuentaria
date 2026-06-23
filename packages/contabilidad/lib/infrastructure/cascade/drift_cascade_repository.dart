/// Drift-backed adapter for [CascadeRepository].
///
/// Stores the single cascade plan as a JSON blob in [CascadeConfig]
/// (singleton row with rowId = 'singleton').  LWW by [updatedAt] µs.
library;

import 'dart:convert';

import 'package:contabilidad/application/cascade/cascade.dart';
import 'package:contabilidad/application/cascade/cascade_repository.dart';
import 'package:contabilidad/application/cascade/cascade_step.dart';
import 'package:contabilidad/infrastructure/database/cuentaria_database.dart';
import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:shared_kernel/shared_kernel.dart';

const _kSingleton = 'singleton';

class DriftCascadeRepository implements CascadeRepository {
  final CuentariaDatabase _db;

  Cascade? _cache;

  DriftCascadeRepository(this._db);

  /// Must be called once after the database is opened to prime the cache.
  Future<void> hydrate() async {
    final row =
        await (_db.select(_db.cascadeConfig)
          ..where((t) => t.rowId.equals(_kSingleton))).getSingleOrNull();
    _cache = row != null ? _rowToCascade(row) : null;
  }

  @override
  Future<Cascade?> load() async => _cache;

  @override
  Future<void> save(Cascade cascade) async {
    final merged = _cache != null ? _cache!.mergeWith(cascade) : cascade;
    await _db
        .into(_db.cascadeConfig)
        .insertOnConflictUpdate(
          CascadeConfigCompanion(
            rowId: const Value(_kSingleton),
            steps: Value(jsonEncode(_stepsToJson(merged.steps))),
            updatedAt: Value(merged.updatedAt.microsecondsSinceEpoch),
          ),
        );
    _cache = merged;
  }

  // ---------------------------------------------------------------------------
  // Codec: Cascade ↔ DB row
  // ---------------------------------------------------------------------------

  Cascade _rowToCascade(CascadeConfigRow row) => Cascade(
    steps: _stepsFromJson(
      (jsonDecode(row.steps) as List).cast<Map<String, dynamic>>(),
    ),
    updatedAt: DateTime.fromMicrosecondsSinceEpoch(row.updatedAt, isUtc: true),
  );

  List<Map<String, dynamic>> _stepsToJson(List<CascadeStep> steps) =>
      steps.map(_stepToJson).toList();

  Map<String, dynamic> _stepToJson(CascadeStep step) => switch (step) {
    FixedStep(:final envelopeId, :final amountUsd) => {
      'type': 'fixed',
      'envelope_id': envelopeId.value,
      'amount_usd': amountUsd,
    },
    FillToCapStep(:final envelopeId) => {
      'type': 'fill_to_cap',
      'envelope_id': envelopeId.value,
    },
    PercentOfRemainderStep(:final envelopeId, :final percent, :final base) => {
      'type': 'percent_of_remainder',
      'envelope_id': envelopeId.value,
      'percent': percent.toString(),
      'base': base.name,
    },
    CatchAllStep(:final envelopeId) => {
      'type': 'catch_all',
      'envelope_id': envelopeId.value,
    },
  };

  List<CascadeStep> _stepsFromJson(List<Map<String, dynamic>> json) =>
      json.map(_stepFromJson).toList();

  CascadeStep _stepFromJson(Map<String, dynamic> j) {
    final type = j['type'] as String;
    final envelopeId = EnvelopeId(j['envelope_id'] as String);
    return switch (type) {
      'fixed' => CascadeStep.fixed(
        envelopeId: envelopeId,
        amountUsd: j['amount_usd'] as int,
      ),
      'fill_to_cap' => CascadeStep.fillToCap(envelopeId: envelopeId),
      'percent_of_remainder' => CascadeStep.percentOfRemainder(
        envelopeId: envelopeId,
        percent: Decimal.parse(j['percent'] as String),
        base: PercentBase.values.byName(j['base'] as String),
      ),
      'catch_all' => CascadeStep.catchAll(envelopeId: envelopeId),
      _ => throw FormatException('Unknown CascadeStep type: $type'),
    };
  }
}
