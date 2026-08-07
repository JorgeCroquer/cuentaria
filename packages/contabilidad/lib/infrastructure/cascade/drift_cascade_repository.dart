/// Drift-backed adapter for [CascadeRepository].
///
/// Stores the single cascade plan as a JSON blob in [CascadeConfig]
/// (singleton row with rowId = 'singleton').  LWW by [updatedAt] µs.
library;

import 'dart:convert';

import 'package:contabilidad/application/cascade/cascade.dart';
import 'package:contabilidad/application/cascade/cascade_codec.dart';
import 'package:contabilidad/application/cascade/cascade_repository.dart';
import 'package:contabilidad/infrastructure/database/cuentaria_database.dart';
import 'package:drift/drift.dart';

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
            steps: Value(jsonEncode(CascadeCodec.stepsToJson(merged.steps))),
            updatedAt: Value(merged.updatedAt.microsecondsSinceEpoch),
          ),
        );
    _cache = merged;
  }

  Cascade _rowToCascade(CascadeConfigRow row) => Cascade(
    steps: CascadeCodec.stepsFromJson(
      (jsonDecode(row.steps) as List).cast<Map<String, dynamic>>(),
    ),
    updatedAt: DateTime.fromMicrosecondsSinceEpoch(row.updatedAt, isUtc: true),
  );
}
