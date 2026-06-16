// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cuentaria_database.dart';

// ignore_for_file: type=lint
class $EventsTable extends Events with TableInfo<$EventsTable, Event> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _eventIdMeta = const VerificationMeta(
    'eventId',
  );
  @override
  late final GeneratedColumn<String> eventId = GeneratedColumn<String>(
    'event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _occurredAtMeta = const VerificationMeta(
    'occurredAt',
  );
  @override
  late final GeneratedColumn<int> occurredAt = GeneratedColumn<int>(
    'occurred_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordedAtMeta = const VerificationMeta(
    'recordedAt',
  );
  @override
  late final GeneratedColumn<int> recordedAt = GeneratedColumn<int>(
    'recorded_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _schemaVersionMeta = const VerificationMeta(
    'schemaVersion',
  );
  @override
  late final GeneratedColumn<int> schemaVersion = GeneratedColumn<int>(
    'schema_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reversesMeta = const VerificationMeta(
    'reverses',
  );
  @override
  late final GeneratedColumn<String> reverses = GeneratedColumn<String>(
    'reverses',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    eventId,
    type,
    occurredAt,
    recordedAt,
    schemaVersion,
    reverses,
    payload,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'events';
  @override
  VerificationContext validateIntegrity(
    Insertable<Event> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('event_id')) {
      context.handle(
        _eventIdMeta,
        eventId.isAcceptableOrUnknown(data['event_id']!, _eventIdMeta),
      );
    } else if (isInserting) {
      context.missing(_eventIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('occurred_at')) {
      context.handle(
        _occurredAtMeta,
        occurredAt.isAcceptableOrUnknown(data['occurred_at']!, _occurredAtMeta),
      );
    } else if (isInserting) {
      context.missing(_occurredAtMeta);
    }
    if (data.containsKey('recorded_at')) {
      context.handle(
        _recordedAtMeta,
        recordedAt.isAcceptableOrUnknown(data['recorded_at']!, _recordedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_recordedAtMeta);
    }
    if (data.containsKey('schema_version')) {
      context.handle(
        _schemaVersionMeta,
        schemaVersion.isAcceptableOrUnknown(
          data['schema_version']!,
          _schemaVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_schemaVersionMeta);
    }
    if (data.containsKey('reverses')) {
      context.handle(
        _reversesMeta,
        reverses.isAcceptableOrUnknown(data['reverses']!, _reversesMeta),
      );
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {eventId};
  @override
  Event map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Event(
      eventId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}event_id'],
          )!,
      type:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}type'],
          )!,
      occurredAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}occurred_at'],
          )!,
      recordedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}recorded_at'],
          )!,
      schemaVersion:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}schema_version'],
          )!,
      reverses: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reverses'],
      ),
      payload:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}payload'],
          )!,
    );
  }

  @override
  $EventsTable createAlias(String alias) {
    return $EventsTable(attachedDatabase, alias);
  }
}

class Event extends DataClass implements Insertable<Event> {
  final String eventId;
  final String type;
  final int occurredAt;
  final int recordedAt;
  final int schemaVersion;
  final String? reverses;
  final String payload;
  const Event({
    required this.eventId,
    required this.type,
    required this.occurredAt,
    required this.recordedAt,
    required this.schemaVersion,
    this.reverses,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['event_id'] = Variable<String>(eventId);
    map['type'] = Variable<String>(type);
    map['occurred_at'] = Variable<int>(occurredAt);
    map['recorded_at'] = Variable<int>(recordedAt);
    map['schema_version'] = Variable<int>(schemaVersion);
    if (!nullToAbsent || reverses != null) {
      map['reverses'] = Variable<String>(reverses);
    }
    map['payload'] = Variable<String>(payload);
    return map;
  }

  EventsCompanion toCompanion(bool nullToAbsent) {
    return EventsCompanion(
      eventId: Value(eventId),
      type: Value(type),
      occurredAt: Value(occurredAt),
      recordedAt: Value(recordedAt),
      schemaVersion: Value(schemaVersion),
      reverses:
          reverses == null && nullToAbsent
              ? const Value.absent()
              : Value(reverses),
      payload: Value(payload),
    );
  }

  factory Event.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Event(
      eventId: serializer.fromJson<String>(json['eventId']),
      type: serializer.fromJson<String>(json['type']),
      occurredAt: serializer.fromJson<int>(json['occurredAt']),
      recordedAt: serializer.fromJson<int>(json['recordedAt']),
      schemaVersion: serializer.fromJson<int>(json['schemaVersion']),
      reverses: serializer.fromJson<String?>(json['reverses']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'eventId': serializer.toJson<String>(eventId),
      'type': serializer.toJson<String>(type),
      'occurredAt': serializer.toJson<int>(occurredAt),
      'recordedAt': serializer.toJson<int>(recordedAt),
      'schemaVersion': serializer.toJson<int>(schemaVersion),
      'reverses': serializer.toJson<String?>(reverses),
      'payload': serializer.toJson<String>(payload),
    };
  }

  Event copyWith({
    String? eventId,
    String? type,
    int? occurredAt,
    int? recordedAt,
    int? schemaVersion,
    Value<String?> reverses = const Value.absent(),
    String? payload,
  }) => Event(
    eventId: eventId ?? this.eventId,
    type: type ?? this.type,
    occurredAt: occurredAt ?? this.occurredAt,
    recordedAt: recordedAt ?? this.recordedAt,
    schemaVersion: schemaVersion ?? this.schemaVersion,
    reverses: reverses.present ? reverses.value : this.reverses,
    payload: payload ?? this.payload,
  );
  Event copyWithCompanion(EventsCompanion data) {
    return Event(
      eventId: data.eventId.present ? data.eventId.value : this.eventId,
      type: data.type.present ? data.type.value : this.type,
      occurredAt:
          data.occurredAt.present ? data.occurredAt.value : this.occurredAt,
      recordedAt:
          data.recordedAt.present ? data.recordedAt.value : this.recordedAt,
      schemaVersion:
          data.schemaVersion.present
              ? data.schemaVersion.value
              : this.schemaVersion,
      reverses: data.reverses.present ? data.reverses.value : this.reverses,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Event(')
          ..write('eventId: $eventId, ')
          ..write('type: $type, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('recordedAt: $recordedAt, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('reverses: $reverses, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    eventId,
    type,
    occurredAt,
    recordedAt,
    schemaVersion,
    reverses,
    payload,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Event &&
          other.eventId == this.eventId &&
          other.type == this.type &&
          other.occurredAt == this.occurredAt &&
          other.recordedAt == this.recordedAt &&
          other.schemaVersion == this.schemaVersion &&
          other.reverses == this.reverses &&
          other.payload == this.payload);
}

class EventsCompanion extends UpdateCompanion<Event> {
  final Value<String> eventId;
  final Value<String> type;
  final Value<int> occurredAt;
  final Value<int> recordedAt;
  final Value<int> schemaVersion;
  final Value<String?> reverses;
  final Value<String> payload;
  final Value<int> rowid;
  const EventsCompanion({
    this.eventId = const Value.absent(),
    this.type = const Value.absent(),
    this.occurredAt = const Value.absent(),
    this.recordedAt = const Value.absent(),
    this.schemaVersion = const Value.absent(),
    this.reverses = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EventsCompanion.insert({
    required String eventId,
    required String type,
    required int occurredAt,
    required int recordedAt,
    required int schemaVersion,
    this.reverses = const Value.absent(),
    required String payload,
    this.rowid = const Value.absent(),
  }) : eventId = Value(eventId),
       type = Value(type),
       occurredAt = Value(occurredAt),
       recordedAt = Value(recordedAt),
       schemaVersion = Value(schemaVersion),
       payload = Value(payload);
  static Insertable<Event> custom({
    Expression<String>? eventId,
    Expression<String>? type,
    Expression<int>? occurredAt,
    Expression<int>? recordedAt,
    Expression<int>? schemaVersion,
    Expression<String>? reverses,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (eventId != null) 'event_id': eventId,
      if (type != null) 'type': type,
      if (occurredAt != null) 'occurred_at': occurredAt,
      if (recordedAt != null) 'recorded_at': recordedAt,
      if (schemaVersion != null) 'schema_version': schemaVersion,
      if (reverses != null) 'reverses': reverses,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EventsCompanion copyWith({
    Value<String>? eventId,
    Value<String>? type,
    Value<int>? occurredAt,
    Value<int>? recordedAt,
    Value<int>? schemaVersion,
    Value<String?>? reverses,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return EventsCompanion(
      eventId: eventId ?? this.eventId,
      type: type ?? this.type,
      occurredAt: occurredAt ?? this.occurredAt,
      recordedAt: recordedAt ?? this.recordedAt,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      reverses: reverses ?? this.reverses,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (eventId.present) {
      map['event_id'] = Variable<String>(eventId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (occurredAt.present) {
      map['occurred_at'] = Variable<int>(occurredAt.value);
    }
    if (recordedAt.present) {
      map['recorded_at'] = Variable<int>(recordedAt.value);
    }
    if (schemaVersion.present) {
      map['schema_version'] = Variable<int>(schemaVersion.value);
    }
    if (reverses.present) {
      map['reverses'] = Variable<String>(reverses.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EventsCompanion(')
          ..write('eventId: $eventId, ')
          ..write('type: $type, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('recordedAt: $recordedAt, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('reverses: $reverses, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EventTargetsTable extends EventTargets
    with TableInfo<$EventTargetsTable, EventTarget> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EventTargetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _eventIdMeta = const VerificationMeta(
    'eventId',
  );
  @override
  late final GeneratedColumn<String> eventId = GeneratedColumn<String>(
    'event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dimensionMeta = const VerificationMeta(
    'dimension',
  );
  @override
  late final GeneratedColumn<String> dimension = GeneratedColumn<String>(
    'dimension',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetIdMeta = const VerificationMeta(
    'targetId',
  );
  @override
  late final GeneratedColumn<String> targetId = GeneratedColumn<String>(
    'target_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [eventId, dimension, targetId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'event_targets';
  @override
  VerificationContext validateIntegrity(
    Insertable<EventTarget> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('event_id')) {
      context.handle(
        _eventIdMeta,
        eventId.isAcceptableOrUnknown(data['event_id']!, _eventIdMeta),
      );
    } else if (isInserting) {
      context.missing(_eventIdMeta);
    }
    if (data.containsKey('dimension')) {
      context.handle(
        _dimensionMeta,
        dimension.isAcceptableOrUnknown(data['dimension']!, _dimensionMeta),
      );
    } else if (isInserting) {
      context.missing(_dimensionMeta);
    }
    if (data.containsKey('target_id')) {
      context.handle(
        _targetIdMeta,
        targetId.isAcceptableOrUnknown(data['target_id']!, _targetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_targetIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => const {};
  @override
  EventTarget map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EventTarget(
      eventId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}event_id'],
          )!,
      dimension:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}dimension'],
          )!,
      targetId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}target_id'],
          )!,
    );
  }

  @override
  $EventTargetsTable createAlias(String alias) {
    return $EventTargetsTable(attachedDatabase, alias);
  }
}

class EventTarget extends DataClass implements Insertable<EventTarget> {
  final String eventId;
  final String dimension;
  final String targetId;
  const EventTarget({
    required this.eventId,
    required this.dimension,
    required this.targetId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['event_id'] = Variable<String>(eventId);
    map['dimension'] = Variable<String>(dimension);
    map['target_id'] = Variable<String>(targetId);
    return map;
  }

  EventTargetsCompanion toCompanion(bool nullToAbsent) {
    return EventTargetsCompanion(
      eventId: Value(eventId),
      dimension: Value(dimension),
      targetId: Value(targetId),
    );
  }

  factory EventTarget.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EventTarget(
      eventId: serializer.fromJson<String>(json['eventId']),
      dimension: serializer.fromJson<String>(json['dimension']),
      targetId: serializer.fromJson<String>(json['targetId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'eventId': serializer.toJson<String>(eventId),
      'dimension': serializer.toJson<String>(dimension),
      'targetId': serializer.toJson<String>(targetId),
    };
  }

  EventTarget copyWith({
    String? eventId,
    String? dimension,
    String? targetId,
  }) => EventTarget(
    eventId: eventId ?? this.eventId,
    dimension: dimension ?? this.dimension,
    targetId: targetId ?? this.targetId,
  );
  EventTarget copyWithCompanion(EventTargetsCompanion data) {
    return EventTarget(
      eventId: data.eventId.present ? data.eventId.value : this.eventId,
      dimension: data.dimension.present ? data.dimension.value : this.dimension,
      targetId: data.targetId.present ? data.targetId.value : this.targetId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EventTarget(')
          ..write('eventId: $eventId, ')
          ..write('dimension: $dimension, ')
          ..write('targetId: $targetId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(eventId, dimension, targetId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EventTarget &&
          other.eventId == this.eventId &&
          other.dimension == this.dimension &&
          other.targetId == this.targetId);
}

class EventTargetsCompanion extends UpdateCompanion<EventTarget> {
  final Value<String> eventId;
  final Value<String> dimension;
  final Value<String> targetId;
  final Value<int> rowid;
  const EventTargetsCompanion({
    this.eventId = const Value.absent(),
    this.dimension = const Value.absent(),
    this.targetId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EventTargetsCompanion.insert({
    required String eventId,
    required String dimension,
    required String targetId,
    this.rowid = const Value.absent(),
  }) : eventId = Value(eventId),
       dimension = Value(dimension),
       targetId = Value(targetId);
  static Insertable<EventTarget> custom({
    Expression<String>? eventId,
    Expression<String>? dimension,
    Expression<String>? targetId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (eventId != null) 'event_id': eventId,
      if (dimension != null) 'dimension': dimension,
      if (targetId != null) 'target_id': targetId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EventTargetsCompanion copyWith({
    Value<String>? eventId,
    Value<String>? dimension,
    Value<String>? targetId,
    Value<int>? rowid,
  }) {
    return EventTargetsCompanion(
      eventId: eventId ?? this.eventId,
      dimension: dimension ?? this.dimension,
      targetId: targetId ?? this.targetId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (eventId.present) {
      map['event_id'] = Variable<String>(eventId.value);
    }
    if (dimension.present) {
      map['dimension'] = Variable<String>(dimension.value);
    }
    if (targetId.present) {
      map['target_id'] = Variable<String>(targetId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EventTargetsCompanion(')
          ..write('eventId: $eventId, ')
          ..write('dimension: $dimension, ')
          ..write('targetId: $targetId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$CuentariaDatabase extends GeneratedDatabase {
  _$CuentariaDatabase(QueryExecutor e) : super(e);
  $CuentariaDatabaseManager get managers => $CuentariaDatabaseManager(this);
  late final $EventsTable events = $EventsTable(this);
  late final $EventTargetsTable eventTargets = $EventTargetsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [events, eventTargets];
}

typedef $$EventsTableCreateCompanionBuilder =
    EventsCompanion Function({
      required String eventId,
      required String type,
      required int occurredAt,
      required int recordedAt,
      required int schemaVersion,
      Value<String?> reverses,
      required String payload,
      Value<int> rowid,
    });
typedef $$EventsTableUpdateCompanionBuilder =
    EventsCompanion Function({
      Value<String> eventId,
      Value<String> type,
      Value<int> occurredAt,
      Value<int> recordedAt,
      Value<int> schemaVersion,
      Value<String?> reverses,
      Value<String> payload,
      Value<int> rowid,
    });

class $$EventsTableFilterComposer
    extends Composer<_$CuentariaDatabase, $EventsTable> {
  $$EventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reverses => $composableBuilder(
    column: $table.reverses,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EventsTableOrderingComposer
    extends Composer<_$CuentariaDatabase, $EventsTable> {
  $$EventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reverses => $composableBuilder(
    column: $table.reverses,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EventsTableAnnotationComposer
    extends Composer<_$CuentariaDatabase, $EventsTable> {
  $$EventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get eventId =>
      $composableBuilder(column: $table.eventId, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reverses =>
      $composableBuilder(column: $table.reverses, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$EventsTableTableManager
    extends
        RootTableManager<
          _$CuentariaDatabase,
          $EventsTable,
          Event,
          $$EventsTableFilterComposer,
          $$EventsTableOrderingComposer,
          $$EventsTableAnnotationComposer,
          $$EventsTableCreateCompanionBuilder,
          $$EventsTableUpdateCompanionBuilder,
          (Event, BaseReferences<_$CuentariaDatabase, $EventsTable, Event>),
          Event,
          PrefetchHooks Function()
        > {
  $$EventsTableTableManager(_$CuentariaDatabase db, $EventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$EventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$EventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$EventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> eventId = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<int> occurredAt = const Value.absent(),
                Value<int> recordedAt = const Value.absent(),
                Value<int> schemaVersion = const Value.absent(),
                Value<String?> reverses = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EventsCompanion(
                eventId: eventId,
                type: type,
                occurredAt: occurredAt,
                recordedAt: recordedAt,
                schemaVersion: schemaVersion,
                reverses: reverses,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String eventId,
                required String type,
                required int occurredAt,
                required int recordedAt,
                required int schemaVersion,
                Value<String?> reverses = const Value.absent(),
                required String payload,
                Value<int> rowid = const Value.absent(),
              }) => EventsCompanion.insert(
                eventId: eventId,
                type: type,
                occurredAt: occurredAt,
                recordedAt: recordedAt,
                schemaVersion: schemaVersion,
                reverses: reverses,
                payload: payload,
                rowid: rowid,
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

typedef $$EventsTableProcessedTableManager =
    ProcessedTableManager<
      _$CuentariaDatabase,
      $EventsTable,
      Event,
      $$EventsTableFilterComposer,
      $$EventsTableOrderingComposer,
      $$EventsTableAnnotationComposer,
      $$EventsTableCreateCompanionBuilder,
      $$EventsTableUpdateCompanionBuilder,
      (Event, BaseReferences<_$CuentariaDatabase, $EventsTable, Event>),
      Event,
      PrefetchHooks Function()
    >;
typedef $$EventTargetsTableCreateCompanionBuilder =
    EventTargetsCompanion Function({
      required String eventId,
      required String dimension,
      required String targetId,
      Value<int> rowid,
    });
typedef $$EventTargetsTableUpdateCompanionBuilder =
    EventTargetsCompanion Function({
      Value<String> eventId,
      Value<String> dimension,
      Value<String> targetId,
      Value<int> rowid,
    });

class $$EventTargetsTableFilterComposer
    extends Composer<_$CuentariaDatabase, $EventTargetsTable> {
  $$EventTargetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dimension => $composableBuilder(
    column: $table.dimension,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EventTargetsTableOrderingComposer
    extends Composer<_$CuentariaDatabase, $EventTargetsTable> {
  $$EventTargetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dimension => $composableBuilder(
    column: $table.dimension,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EventTargetsTableAnnotationComposer
    extends Composer<_$CuentariaDatabase, $EventTargetsTable> {
  $$EventTargetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get eventId =>
      $composableBuilder(column: $table.eventId, builder: (column) => column);

  GeneratedColumn<String> get dimension =>
      $composableBuilder(column: $table.dimension, builder: (column) => column);

  GeneratedColumn<String> get targetId =>
      $composableBuilder(column: $table.targetId, builder: (column) => column);
}

class $$EventTargetsTableTableManager
    extends
        RootTableManager<
          _$CuentariaDatabase,
          $EventTargetsTable,
          EventTarget,
          $$EventTargetsTableFilterComposer,
          $$EventTargetsTableOrderingComposer,
          $$EventTargetsTableAnnotationComposer,
          $$EventTargetsTableCreateCompanionBuilder,
          $$EventTargetsTableUpdateCompanionBuilder,
          (
            EventTarget,
            BaseReferences<
              _$CuentariaDatabase,
              $EventTargetsTable,
              EventTarget
            >,
          ),
          EventTarget,
          PrefetchHooks Function()
        > {
  $$EventTargetsTableTableManager(
    _$CuentariaDatabase db,
    $EventTargetsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$EventTargetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$EventTargetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () =>
                  $$EventTargetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> eventId = const Value.absent(),
                Value<String> dimension = const Value.absent(),
                Value<String> targetId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EventTargetsCompanion(
                eventId: eventId,
                dimension: dimension,
                targetId: targetId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String eventId,
                required String dimension,
                required String targetId,
                Value<int> rowid = const Value.absent(),
              }) => EventTargetsCompanion.insert(
                eventId: eventId,
                dimension: dimension,
                targetId: targetId,
                rowid: rowid,
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

typedef $$EventTargetsTableProcessedTableManager =
    ProcessedTableManager<
      _$CuentariaDatabase,
      $EventTargetsTable,
      EventTarget,
      $$EventTargetsTableFilterComposer,
      $$EventTargetsTableOrderingComposer,
      $$EventTargetsTableAnnotationComposer,
      $$EventTargetsTableCreateCompanionBuilder,
      $$EventTargetsTableUpdateCompanionBuilder,
      (
        EventTarget,
        BaseReferences<_$CuentariaDatabase, $EventTargetsTable, EventTarget>,
      ),
      EventTarget,
      PrefetchHooks Function()
    >;

class $CuentariaDatabaseManager {
  final _$CuentariaDatabase _db;
  $CuentariaDatabaseManager(this._db);
  $$EventsTableTableManager get events =>
      $$EventsTableTableManager(_db, _db.events);
  $$EventTargetsTableTableManager get eventTargets =>
      $$EventTargetsTableTableManager(_db, _db.eventTargets);
}
