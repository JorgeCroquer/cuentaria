// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tasas_database.dart';

// ignore_for_file: type=lint
class $RateObservationsTable extends RateObservations
    with TableInfo<$RateObservationsTable, RateObservationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RateObservationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _currencyMeta = const VerificationMeta(
    'currency',
  );
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
    'currency',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nativePerUsdMeta = const VerificationMeta(
    'nativePerUsd',
  );
  @override
  late final GeneratedColumn<String> nativePerUsd = GeneratedColumn<String>(
    'native_per_usd',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _observedAtMeta = const VerificationMeta(
    'observedAt',
  );
  @override
  late final GeneratedColumn<int> observedAt = GeneratedColumn<int>(
    'observed_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    currency,
    nativePerUsd,
    observedAt,
    source,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'rate_observations';
  @override
  VerificationContext validateIntegrity(
    Insertable<RateObservationRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('currency')) {
      context.handle(
        _currencyMeta,
        currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta),
      );
    } else if (isInserting) {
      context.missing(_currencyMeta);
    }
    if (data.containsKey('native_per_usd')) {
      context.handle(
        _nativePerUsdMeta,
        nativePerUsd.isAcceptableOrUnknown(
          data['native_per_usd']!,
          _nativePerUsdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_nativePerUsdMeta);
    }
    if (data.containsKey('observed_at')) {
      context.handle(
        _observedAtMeta,
        observedAt.isAcceptableOrUnknown(data['observed_at']!, _observedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_observedAtMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RateObservationRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RateObservationRow(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      currency:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}currency'],
          )!,
      nativePerUsd:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}native_per_usd'],
          )!,
      observedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}observed_at'],
          )!,
      source:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}source'],
          )!,
    );
  }

  @override
  $RateObservationsTable createAlias(String alias) {
    return $RateObservationsTable(attachedDatabase, alias);
  }
}

class RateObservationRow extends DataClass
    implements Insertable<RateObservationRow> {
  final int id;
  final String currency;
  final String nativePerUsd;
  final int observedAt;
  final String source;
  const RateObservationRow({
    required this.id,
    required this.currency,
    required this.nativePerUsd,
    required this.observedAt,
    required this.source,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['currency'] = Variable<String>(currency);
    map['native_per_usd'] = Variable<String>(nativePerUsd);
    map['observed_at'] = Variable<int>(observedAt);
    map['source'] = Variable<String>(source);
    return map;
  }

  RateObservationsCompanion toCompanion(bool nullToAbsent) {
    return RateObservationsCompanion(
      id: Value(id),
      currency: Value(currency),
      nativePerUsd: Value(nativePerUsd),
      observedAt: Value(observedAt),
      source: Value(source),
    );
  }

  factory RateObservationRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RateObservationRow(
      id: serializer.fromJson<int>(json['id']),
      currency: serializer.fromJson<String>(json['currency']),
      nativePerUsd: serializer.fromJson<String>(json['nativePerUsd']),
      observedAt: serializer.fromJson<int>(json['observedAt']),
      source: serializer.fromJson<String>(json['source']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'currency': serializer.toJson<String>(currency),
      'nativePerUsd': serializer.toJson<String>(nativePerUsd),
      'observedAt': serializer.toJson<int>(observedAt),
      'source': serializer.toJson<String>(source),
    };
  }

  RateObservationRow copyWith({
    int? id,
    String? currency,
    String? nativePerUsd,
    int? observedAt,
    String? source,
  }) => RateObservationRow(
    id: id ?? this.id,
    currency: currency ?? this.currency,
    nativePerUsd: nativePerUsd ?? this.nativePerUsd,
    observedAt: observedAt ?? this.observedAt,
    source: source ?? this.source,
  );
  RateObservationRow copyWithCompanion(RateObservationsCompanion data) {
    return RateObservationRow(
      id: data.id.present ? data.id.value : this.id,
      currency: data.currency.present ? data.currency.value : this.currency,
      nativePerUsd:
          data.nativePerUsd.present
              ? data.nativePerUsd.value
              : this.nativePerUsd,
      observedAt:
          data.observedAt.present ? data.observedAt.value : this.observedAt,
      source: data.source.present ? data.source.value : this.source,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RateObservationRow(')
          ..write('id: $id, ')
          ..write('currency: $currency, ')
          ..write('nativePerUsd: $nativePerUsd, ')
          ..write('observedAt: $observedAt, ')
          ..write('source: $source')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, currency, nativePerUsd, observedAt, source);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RateObservationRow &&
          other.id == this.id &&
          other.currency == this.currency &&
          other.nativePerUsd == this.nativePerUsd &&
          other.observedAt == this.observedAt &&
          other.source == this.source);
}

class RateObservationsCompanion extends UpdateCompanion<RateObservationRow> {
  final Value<int> id;
  final Value<String> currency;
  final Value<String> nativePerUsd;
  final Value<int> observedAt;
  final Value<String> source;
  const RateObservationsCompanion({
    this.id = const Value.absent(),
    this.currency = const Value.absent(),
    this.nativePerUsd = const Value.absent(),
    this.observedAt = const Value.absent(),
    this.source = const Value.absent(),
  });
  RateObservationsCompanion.insert({
    this.id = const Value.absent(),
    required String currency,
    required String nativePerUsd,
    required int observedAt,
    required String source,
  }) : currency = Value(currency),
       nativePerUsd = Value(nativePerUsd),
       observedAt = Value(observedAt),
       source = Value(source);
  static Insertable<RateObservationRow> custom({
    Expression<int>? id,
    Expression<String>? currency,
    Expression<String>? nativePerUsd,
    Expression<int>? observedAt,
    Expression<String>? source,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (currency != null) 'currency': currency,
      if (nativePerUsd != null) 'native_per_usd': nativePerUsd,
      if (observedAt != null) 'observed_at': observedAt,
      if (source != null) 'source': source,
    });
  }

  RateObservationsCompanion copyWith({
    Value<int>? id,
    Value<String>? currency,
    Value<String>? nativePerUsd,
    Value<int>? observedAt,
    Value<String>? source,
  }) {
    return RateObservationsCompanion(
      id: id ?? this.id,
      currency: currency ?? this.currency,
      nativePerUsd: nativePerUsd ?? this.nativePerUsd,
      observedAt: observedAt ?? this.observedAt,
      source: source ?? this.source,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (nativePerUsd.present) {
      map['native_per_usd'] = Variable<String>(nativePerUsd.value);
    }
    if (observedAt.present) {
      map['observed_at'] = Variable<int>(observedAt.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RateObservationsCompanion(')
          ..write('id: $id, ')
          ..write('currency: $currency, ')
          ..write('nativePerUsd: $nativePerUsd, ')
          ..write('observedAt: $observedAt, ')
          ..write('source: $source')
          ..write(')'))
        .toString();
  }
}

abstract class _$TasasDatabase extends GeneratedDatabase {
  _$TasasDatabase(QueryExecutor e) : super(e);
  $TasasDatabaseManager get managers => $TasasDatabaseManager(this);
  late final $RateObservationsTable rateObservations = $RateObservationsTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [rateObservations];
}

typedef $$RateObservationsTableCreateCompanionBuilder =
    RateObservationsCompanion Function({
      Value<int> id,
      required String currency,
      required String nativePerUsd,
      required int observedAt,
      required String source,
    });
typedef $$RateObservationsTableUpdateCompanionBuilder =
    RateObservationsCompanion Function({
      Value<int> id,
      Value<String> currency,
      Value<String> nativePerUsd,
      Value<int> observedAt,
      Value<String> source,
    });

class $$RateObservationsTableFilterComposer
    extends Composer<_$TasasDatabase, $RateObservationsTable> {
  $$RateObservationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nativePerUsd => $composableBuilder(
    column: $table.nativePerUsd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get observedAt => $composableBuilder(
    column: $table.observedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RateObservationsTableOrderingComposer
    extends Composer<_$TasasDatabase, $RateObservationsTable> {
  $$RateObservationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nativePerUsd => $composableBuilder(
    column: $table.nativePerUsd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get observedAt => $composableBuilder(
    column: $table.observedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RateObservationsTableAnnotationComposer
    extends Composer<_$TasasDatabase, $RateObservationsTable> {
  $$RateObservationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<String> get nativePerUsd => $composableBuilder(
    column: $table.nativePerUsd,
    builder: (column) => column,
  );

  GeneratedColumn<int> get observedAt => $composableBuilder(
    column: $table.observedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);
}

class $$RateObservationsTableTableManager
    extends
        RootTableManager<
          _$TasasDatabase,
          $RateObservationsTable,
          RateObservationRow,
          $$RateObservationsTableFilterComposer,
          $$RateObservationsTableOrderingComposer,
          $$RateObservationsTableAnnotationComposer,
          $$RateObservationsTableCreateCompanionBuilder,
          $$RateObservationsTableUpdateCompanionBuilder,
          (
            RateObservationRow,
            BaseReferences<
              _$TasasDatabase,
              $RateObservationsTable,
              RateObservationRow
            >,
          ),
          RateObservationRow,
          PrefetchHooks Function()
        > {
  $$RateObservationsTableTableManager(
    _$TasasDatabase db,
    $RateObservationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () =>
                  $$RateObservationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$RateObservationsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer:
              () => $$RateObservationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> currency = const Value.absent(),
                Value<String> nativePerUsd = const Value.absent(),
                Value<int> observedAt = const Value.absent(),
                Value<String> source = const Value.absent(),
              }) => RateObservationsCompanion(
                id: id,
                currency: currency,
                nativePerUsd: nativePerUsd,
                observedAt: observedAt,
                source: source,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String currency,
                required String nativePerUsd,
                required int observedAt,
                required String source,
              }) => RateObservationsCompanion.insert(
                id: id,
                currency: currency,
                nativePerUsd: nativePerUsd,
                observedAt: observedAt,
                source: source,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RateObservationsTableProcessedTableManager =
    ProcessedTableManager<
      _$TasasDatabase,
      $RateObservationsTable,
      RateObservationRow,
      $$RateObservationsTableFilterComposer,
      $$RateObservationsTableOrderingComposer,
      $$RateObservationsTableAnnotationComposer,
      $$RateObservationsTableCreateCompanionBuilder,
      $$RateObservationsTableUpdateCompanionBuilder,
      (
        RateObservationRow,
        BaseReferences<
          _$TasasDatabase,
          $RateObservationsTable,
          RateObservationRow
        >,
      ),
      RateObservationRow,
      PrefetchHooks Function()
    >;

class $TasasDatabaseManager {
  final _$TasasDatabase _db;
  $TasasDatabaseManager(this._db);
  $$RateObservationsTableTableManager get rateObservations =>
      $$RateObservationsTableTableManager(_db, _db.rateObservations);
}
