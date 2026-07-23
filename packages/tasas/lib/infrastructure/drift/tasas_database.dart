/// Drift database for the `tasas` context — schema v1.
///
/// Its own small, **unencrypted** database (ADR-0016 §3): exchange rate
/// observations are public data, so this store never shares the encrypted
/// ledger database and never touches SQLCipher/key plumbing.
///
/// [QueryExecutor] is injected so tests can use [NativeDatabase.memory()]
/// and the app can open a plain SQLite file on native platforms.
library;

import 'package:drift/drift.dart';

part 'tasas_database.g.dart';

/// Append-only log of observed exchange rates (ADR-0016).
///
/// [id] is an autoincrement rowid used only to break ties between
/// observations sharing the same [observedAt]: the highest [id] is the
/// most recently appended row.
@DataClassName('RateObservationRow')
class RateObservations extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get currency => text()();
  TextColumn get nativePerUsd => text()(); // Decimal, serialized
  IntColumn get observedAt => integer()(); // epoch µs
  TextColumn get source => text()();
}

@DriftDatabase(tables: [RateObservations])
class TasasDatabase extends _$TasasDatabase {
  TasasDatabase(super.e);

  @override
  int get schemaVersion => 1;
}
