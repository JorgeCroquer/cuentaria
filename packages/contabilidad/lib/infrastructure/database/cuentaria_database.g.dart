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

class $AccountsTable extends Accounts
    with TableInfo<$AccountsTable, AccountRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AccountsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nativeCurrencyMeta = const VerificationMeta(
    'nativeCurrency',
  );
  @override
  late final GeneratedColumn<String> nativeCurrency = GeneratedColumn<String>(
    'native_currency',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _providerMeta = const VerificationMeta(
    'provider',
  );
  @override
  late final GeneratedColumn<String> provider = GeneratedColumn<String>(
    'provider',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isArchivedMeta = const VerificationMeta(
    'isArchived',
  );
  @override
  late final GeneratedColumn<bool> isArchived = GeneratedColumn<bool>(
    'is_archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_archived" IN (0, 1))',
    ),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _metaMeta = const VerificationMeta('meta');
  @override
  late final GeneratedColumn<String> meta = GeneratedColumn<String>(
    'meta',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    nativeCurrency,
    provider,
    isArchived,
    updatedAt,
    meta,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'accounts';
  @override
  VerificationContext validateIntegrity(
    Insertable<AccountRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('native_currency')) {
      context.handle(
        _nativeCurrencyMeta,
        nativeCurrency.isAcceptableOrUnknown(
          data['native_currency']!,
          _nativeCurrencyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_nativeCurrencyMeta);
    }
    if (data.containsKey('provider')) {
      context.handle(
        _providerMeta,
        provider.isAcceptableOrUnknown(data['provider']!, _providerMeta),
      );
    }
    if (data.containsKey('is_archived')) {
      context.handle(
        _isArchivedMeta,
        isArchived.isAcceptableOrUnknown(data['is_archived']!, _isArchivedMeta),
      );
    } else if (isInserting) {
      context.missing(_isArchivedMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('meta')) {
      context.handle(
        _metaMeta,
        meta.isAcceptableOrUnknown(data['meta']!, _metaMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AccountRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AccountRow(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}id'],
          )!,
      name:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}name'],
          )!,
      nativeCurrency:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}native_currency'],
          )!,
      provider: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider'],
      ),
      isArchived:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}is_archived'],
          )!,
      updatedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}updated_at'],
          )!,
      meta: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}meta'],
      ),
    );
  }

  @override
  $AccountsTable createAlias(String alias) {
    return $AccountsTable(attachedDatabase, alias);
  }
}

class AccountRow extends DataClass implements Insertable<AccountRow> {
  final String id;
  final String name;
  final String nativeCurrency;
  final String? provider;
  final bool isArchived;
  final int updatedAt;
  final String? meta;
  const AccountRow({
    required this.id,
    required this.name,
    required this.nativeCurrency,
    this.provider,
    required this.isArchived,
    required this.updatedAt,
    this.meta,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['native_currency'] = Variable<String>(nativeCurrency);
    if (!nullToAbsent || provider != null) {
      map['provider'] = Variable<String>(provider);
    }
    map['is_archived'] = Variable<bool>(isArchived);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || meta != null) {
      map['meta'] = Variable<String>(meta);
    }
    return map;
  }

  AccountsCompanion toCompanion(bool nullToAbsent) {
    return AccountsCompanion(
      id: Value(id),
      name: Value(name),
      nativeCurrency: Value(nativeCurrency),
      provider:
          provider == null && nullToAbsent
              ? const Value.absent()
              : Value(provider),
      isArchived: Value(isArchived),
      updatedAt: Value(updatedAt),
      meta: meta == null && nullToAbsent ? const Value.absent() : Value(meta),
    );
  }

  factory AccountRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AccountRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      nativeCurrency: serializer.fromJson<String>(json['nativeCurrency']),
      provider: serializer.fromJson<String?>(json['provider']),
      isArchived: serializer.fromJson<bool>(json['isArchived']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      meta: serializer.fromJson<String?>(json['meta']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'nativeCurrency': serializer.toJson<String>(nativeCurrency),
      'provider': serializer.toJson<String?>(provider),
      'isArchived': serializer.toJson<bool>(isArchived),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'meta': serializer.toJson<String?>(meta),
    };
  }

  AccountRow copyWith({
    String? id,
    String? name,
    String? nativeCurrency,
    Value<String?> provider = const Value.absent(),
    bool? isArchived,
    int? updatedAt,
    Value<String?> meta = const Value.absent(),
  }) => AccountRow(
    id: id ?? this.id,
    name: name ?? this.name,
    nativeCurrency: nativeCurrency ?? this.nativeCurrency,
    provider: provider.present ? provider.value : this.provider,
    isArchived: isArchived ?? this.isArchived,
    updatedAt: updatedAt ?? this.updatedAt,
    meta: meta.present ? meta.value : this.meta,
  );
  AccountRow copyWithCompanion(AccountsCompanion data) {
    return AccountRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      nativeCurrency:
          data.nativeCurrency.present
              ? data.nativeCurrency.value
              : this.nativeCurrency,
      provider: data.provider.present ? data.provider.value : this.provider,
      isArchived:
          data.isArchived.present ? data.isArchived.value : this.isArchived,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      meta: data.meta.present ? data.meta.value : this.meta,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AccountRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('nativeCurrency: $nativeCurrency, ')
          ..write('provider: $provider, ')
          ..write('isArchived: $isArchived, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('meta: $meta')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    nativeCurrency,
    provider,
    isArchived,
    updatedAt,
    meta,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AccountRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.nativeCurrency == this.nativeCurrency &&
          other.provider == this.provider &&
          other.isArchived == this.isArchived &&
          other.updatedAt == this.updatedAt &&
          other.meta == this.meta);
}

class AccountsCompanion extends UpdateCompanion<AccountRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> nativeCurrency;
  final Value<String?> provider;
  final Value<bool> isArchived;
  final Value<int> updatedAt;
  final Value<String?> meta;
  final Value<int> rowid;
  const AccountsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.nativeCurrency = const Value.absent(),
    this.provider = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.meta = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AccountsCompanion.insert({
    required String id,
    required String name,
    required String nativeCurrency,
    this.provider = const Value.absent(),
    required bool isArchived,
    required int updatedAt,
    this.meta = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       nativeCurrency = Value(nativeCurrency),
       isArchived = Value(isArchived),
       updatedAt = Value(updatedAt);
  static Insertable<AccountRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? nativeCurrency,
    Expression<String>? provider,
    Expression<bool>? isArchived,
    Expression<int>? updatedAt,
    Expression<String>? meta,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (nativeCurrency != null) 'native_currency': nativeCurrency,
      if (provider != null) 'provider': provider,
      if (isArchived != null) 'is_archived': isArchived,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (meta != null) 'meta': meta,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AccountsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? nativeCurrency,
    Value<String?>? provider,
    Value<bool>? isArchived,
    Value<int>? updatedAt,
    Value<String?>? meta,
    Value<int>? rowid,
  }) {
    return AccountsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      nativeCurrency: nativeCurrency ?? this.nativeCurrency,
      provider: provider ?? this.provider,
      isArchived: isArchived ?? this.isArchived,
      updatedAt: updatedAt ?? this.updatedAt,
      meta: meta ?? this.meta,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (nativeCurrency.present) {
      map['native_currency'] = Variable<String>(nativeCurrency.value);
    }
    if (provider.present) {
      map['provider'] = Variable<String>(provider.value);
    }
    if (isArchived.present) {
      map['is_archived'] = Variable<bool>(isArchived.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (meta.present) {
      map['meta'] = Variable<String>(meta.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AccountsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('nativeCurrency: $nativeCurrency, ')
          ..write('provider: $provider, ')
          ..write('isArchived: $isArchived, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('meta: $meta, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EnvelopesTable extends Envelopes
    with TableInfo<$EnvelopesTable, EnvelopeRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EnvelopesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isArchivedMeta = const VerificationMeta(
    'isArchived',
  );
  @override
  late final GeneratedColumn<bool> isArchived = GeneratedColumn<bool>(
    'is_archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_archived" IN (0, 1))',
    ),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _metaMeta = const VerificationMeta('meta');
  @override
  late final GeneratedColumn<String> meta = GeneratedColumn<String>(
    'meta',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    role,
    isArchived,
    updatedAt,
    meta,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'envelopes';
  @override
  VerificationContext validateIntegrity(
    Insertable<EnvelopeRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('is_archived')) {
      context.handle(
        _isArchivedMeta,
        isArchived.isAcceptableOrUnknown(data['is_archived']!, _isArchivedMeta),
      );
    } else if (isInserting) {
      context.missing(_isArchivedMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('meta')) {
      context.handle(
        _metaMeta,
        meta.isAcceptableOrUnknown(data['meta']!, _metaMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  EnvelopeRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EnvelopeRow(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}id'],
          )!,
      name:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}name'],
          )!,
      role:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}role'],
          )!,
      isArchived:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}is_archived'],
          )!,
      updatedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}updated_at'],
          )!,
      meta: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}meta'],
      ),
    );
  }

  @override
  $EnvelopesTable createAlias(String alias) {
    return $EnvelopesTable(attachedDatabase, alias);
  }
}

class EnvelopeRow extends DataClass implements Insertable<EnvelopeRow> {
  final String id;
  final String name;
  final String role;
  final bool isArchived;
  final int updatedAt;
  final String? meta;
  const EnvelopeRow({
    required this.id,
    required this.name,
    required this.role,
    required this.isArchived,
    required this.updatedAt,
    this.meta,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['role'] = Variable<String>(role);
    map['is_archived'] = Variable<bool>(isArchived);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || meta != null) {
      map['meta'] = Variable<String>(meta);
    }
    return map;
  }

  EnvelopesCompanion toCompanion(bool nullToAbsent) {
    return EnvelopesCompanion(
      id: Value(id),
      name: Value(name),
      role: Value(role),
      isArchived: Value(isArchived),
      updatedAt: Value(updatedAt),
      meta: meta == null && nullToAbsent ? const Value.absent() : Value(meta),
    );
  }

  factory EnvelopeRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EnvelopeRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      role: serializer.fromJson<String>(json['role']),
      isArchived: serializer.fromJson<bool>(json['isArchived']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      meta: serializer.fromJson<String?>(json['meta']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'role': serializer.toJson<String>(role),
      'isArchived': serializer.toJson<bool>(isArchived),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'meta': serializer.toJson<String?>(meta),
    };
  }

  EnvelopeRow copyWith({
    String? id,
    String? name,
    String? role,
    bool? isArchived,
    int? updatedAt,
    Value<String?> meta = const Value.absent(),
  }) => EnvelopeRow(
    id: id ?? this.id,
    name: name ?? this.name,
    role: role ?? this.role,
    isArchived: isArchived ?? this.isArchived,
    updatedAt: updatedAt ?? this.updatedAt,
    meta: meta.present ? meta.value : this.meta,
  );
  EnvelopeRow copyWithCompanion(EnvelopesCompanion data) {
    return EnvelopeRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      role: data.role.present ? data.role.value : this.role,
      isArchived:
          data.isArchived.present ? data.isArchived.value : this.isArchived,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      meta: data.meta.present ? data.meta.value : this.meta,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EnvelopeRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('role: $role, ')
          ..write('isArchived: $isArchived, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('meta: $meta')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, role, isArchived, updatedAt, meta);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EnvelopeRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.role == this.role &&
          other.isArchived == this.isArchived &&
          other.updatedAt == this.updatedAt &&
          other.meta == this.meta);
}

class EnvelopesCompanion extends UpdateCompanion<EnvelopeRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> role;
  final Value<bool> isArchived;
  final Value<int> updatedAt;
  final Value<String?> meta;
  final Value<int> rowid;
  const EnvelopesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.role = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.meta = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EnvelopesCompanion.insert({
    required String id,
    required String name,
    required String role,
    required bool isArchived,
    required int updatedAt,
    this.meta = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       role = Value(role),
       isArchived = Value(isArchived),
       updatedAt = Value(updatedAt);
  static Insertable<EnvelopeRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? role,
    Expression<bool>? isArchived,
    Expression<int>? updatedAt,
    Expression<String>? meta,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (role != null) 'role': role,
      if (isArchived != null) 'is_archived': isArchived,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (meta != null) 'meta': meta,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EnvelopesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? role,
    Value<bool>? isArchived,
    Value<int>? updatedAt,
    Value<String?>? meta,
    Value<int>? rowid,
  }) {
    return EnvelopesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      role: role ?? this.role,
      isArchived: isArchived ?? this.isArchived,
      updatedAt: updatedAt ?? this.updatedAt,
      meta: meta ?? this.meta,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (isArchived.present) {
      map['is_archived'] = Variable<bool>(isArchived.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (meta.present) {
      map['meta'] = Variable<String>(meta.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EnvelopesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('role: $role, ')
          ..write('isArchived: $isArchived, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('meta: $meta, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CascadeConfigTable extends CascadeConfig
    with TableInfo<$CascadeConfigTable, CascadeConfigRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CascadeConfigTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _rowIdMeta = const VerificationMeta('rowId');
  @override
  late final GeneratedColumn<String> rowId = GeneratedColumn<String>(
    'row_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stepsMeta = const VerificationMeta('steps');
  @override
  late final GeneratedColumn<String> steps = GeneratedColumn<String>(
    'steps',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [rowId, steps, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cascade_config';
  @override
  VerificationContext validateIntegrity(
    Insertable<CascadeConfigRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('row_id')) {
      context.handle(
        _rowIdMeta,
        rowId.isAcceptableOrUnknown(data['row_id']!, _rowIdMeta),
      );
    } else if (isInserting) {
      context.missing(_rowIdMeta);
    }
    if (data.containsKey('steps')) {
      context.handle(
        _stepsMeta,
        steps.isAcceptableOrUnknown(data['steps']!, _stepsMeta),
      );
    } else if (isInserting) {
      context.missing(_stepsMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {rowId};
  @override
  CascadeConfigRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CascadeConfigRow(
      rowId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}row_id'],
          )!,
      steps:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}steps'],
          )!,
      updatedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}updated_at'],
          )!,
    );
  }

  @override
  $CascadeConfigTable createAlias(String alias) {
    return $CascadeConfigTable(attachedDatabase, alias);
  }
}

class CascadeConfigRow extends DataClass
    implements Insertable<CascadeConfigRow> {
  final String rowId;
  final String steps;
  final int updatedAt;
  const CascadeConfigRow({
    required this.rowId,
    required this.steps,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['row_id'] = Variable<String>(rowId);
    map['steps'] = Variable<String>(steps);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  CascadeConfigCompanion toCompanion(bool nullToAbsent) {
    return CascadeConfigCompanion(
      rowId: Value(rowId),
      steps: Value(steps),
      updatedAt: Value(updatedAt),
    );
  }

  factory CascadeConfigRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CascadeConfigRow(
      rowId: serializer.fromJson<String>(json['rowId']),
      steps: serializer.fromJson<String>(json['steps']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'rowId': serializer.toJson<String>(rowId),
      'steps': serializer.toJson<String>(steps),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  CascadeConfigRow copyWith({String? rowId, String? steps, int? updatedAt}) =>
      CascadeConfigRow(
        rowId: rowId ?? this.rowId,
        steps: steps ?? this.steps,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  CascadeConfigRow copyWithCompanion(CascadeConfigCompanion data) {
    return CascadeConfigRow(
      rowId: data.rowId.present ? data.rowId.value : this.rowId,
      steps: data.steps.present ? data.steps.value : this.steps,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CascadeConfigRow(')
          ..write('rowId: $rowId, ')
          ..write('steps: $steps, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(rowId, steps, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CascadeConfigRow &&
          other.rowId == this.rowId &&
          other.steps == this.steps &&
          other.updatedAt == this.updatedAt);
}

class CascadeConfigCompanion extends UpdateCompanion<CascadeConfigRow> {
  final Value<String> rowId;
  final Value<String> steps;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const CascadeConfigCompanion({
    this.rowId = const Value.absent(),
    this.steps = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CascadeConfigCompanion.insert({
    required String rowId,
    required String steps,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : rowId = Value(rowId),
       steps = Value(steps),
       updatedAt = Value(updatedAt);
  static Insertable<CascadeConfigRow> custom({
    Expression<String>? rowId,
    Expression<String>? steps,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (rowId != null) 'row_id': rowId,
      if (steps != null) 'steps': steps,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CascadeConfigCompanion copyWith({
    Value<String>? rowId,
    Value<String>? steps,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return CascadeConfigCompanion(
      rowId: rowId ?? this.rowId,
      steps: steps ?? this.steps,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (rowId.present) {
      map['row_id'] = Variable<String>(rowId.value);
    }
    if (steps.present) {
      map['steps'] = Variable<String>(steps.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CascadeConfigCompanion(')
          ..write('rowId: $rowId, ')
          ..write('steps: $steps, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppMetaTable extends AppMeta with TableInfo<$AppMetaTable, AppMetaRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_meta';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppMetaRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppMetaRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppMetaRow(
      key:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}key'],
          )!,
      value:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}value'],
          )!,
    );
  }

  @override
  $AppMetaTable createAlias(String alias) {
    return $AppMetaTable(attachedDatabase, alias);
  }
}

class AppMetaRow extends DataClass implements Insertable<AppMetaRow> {
  final String key;
  final String value;
  const AppMetaRow({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  AppMetaCompanion toCompanion(bool nullToAbsent) {
    return AppMetaCompanion(key: Value(key), value: Value(value));
  }

  factory AppMetaRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppMetaRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  AppMetaRow copyWith({String? key, String? value}) =>
      AppMetaRow(key: key ?? this.key, value: value ?? this.value);
  AppMetaRow copyWithCompanion(AppMetaCompanion data) {
    return AppMetaRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppMetaRow(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppMetaRow &&
          other.key == this.key &&
          other.value == this.value);
}

class AppMetaCompanion extends UpdateCompanion<AppMetaRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const AppMetaCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppMetaCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<AppMetaRow> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppMetaCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return AppMetaCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppMetaCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
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
  late final $AccountsTable accounts = $AccountsTable(this);
  late final $EnvelopesTable envelopes = $EnvelopesTable(this);
  late final $CascadeConfigTable cascadeConfig = $CascadeConfigTable(this);
  late final $AppMetaTable appMeta = $AppMetaTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    events,
    eventTargets,
    accounts,
    envelopes,
    cascadeConfig,
    appMeta,
  ];
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
typedef $$AccountsTableCreateCompanionBuilder =
    AccountsCompanion Function({
      required String id,
      required String name,
      required String nativeCurrency,
      Value<String?> provider,
      required bool isArchived,
      required int updatedAt,
      Value<String?> meta,
      Value<int> rowid,
    });
typedef $$AccountsTableUpdateCompanionBuilder =
    AccountsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> nativeCurrency,
      Value<String?> provider,
      Value<bool> isArchived,
      Value<int> updatedAt,
      Value<String?> meta,
      Value<int> rowid,
    });

class $$AccountsTableFilterComposer
    extends Composer<_$CuentariaDatabase, $AccountsTable> {
  $$AccountsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nativeCurrency => $composableBuilder(
    column: $table.nativeCurrency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get meta => $composableBuilder(
    column: $table.meta,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AccountsTableOrderingComposer
    extends Composer<_$CuentariaDatabase, $AccountsTable> {
  $$AccountsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nativeCurrency => $composableBuilder(
    column: $table.nativeCurrency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get meta => $composableBuilder(
    column: $table.meta,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AccountsTableAnnotationComposer
    extends Composer<_$CuentariaDatabase, $AccountsTable> {
  $$AccountsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get nativeCurrency => $composableBuilder(
    column: $table.nativeCurrency,
    builder: (column) => column,
  );

  GeneratedColumn<String> get provider =>
      $composableBuilder(column: $table.provider, builder: (column) => column);

  GeneratedColumn<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get meta =>
      $composableBuilder(column: $table.meta, builder: (column) => column);
}

class $$AccountsTableTableManager
    extends
        RootTableManager<
          _$CuentariaDatabase,
          $AccountsTable,
          AccountRow,
          $$AccountsTableFilterComposer,
          $$AccountsTableOrderingComposer,
          $$AccountsTableAnnotationComposer,
          $$AccountsTableCreateCompanionBuilder,
          $$AccountsTableUpdateCompanionBuilder,
          (
            AccountRow,
            BaseReferences<_$CuentariaDatabase, $AccountsTable, AccountRow>,
          ),
          AccountRow,
          PrefetchHooks Function()
        > {
  $$AccountsTableTableManager(_$CuentariaDatabase db, $AccountsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$AccountsTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$AccountsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$AccountsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> nativeCurrency = const Value.absent(),
                Value<String?> provider = const Value.absent(),
                Value<bool> isArchived = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<String?> meta = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AccountsCompanion(
                id: id,
                name: name,
                nativeCurrency: nativeCurrency,
                provider: provider,
                isArchived: isArchived,
                updatedAt: updatedAt,
                meta: meta,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String nativeCurrency,
                Value<String?> provider = const Value.absent(),
                required bool isArchived,
                required int updatedAt,
                Value<String?> meta = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AccountsCompanion.insert(
                id: id,
                name: name,
                nativeCurrency: nativeCurrency,
                provider: provider,
                isArchived: isArchived,
                updatedAt: updatedAt,
                meta: meta,
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

typedef $$AccountsTableProcessedTableManager =
    ProcessedTableManager<
      _$CuentariaDatabase,
      $AccountsTable,
      AccountRow,
      $$AccountsTableFilterComposer,
      $$AccountsTableOrderingComposer,
      $$AccountsTableAnnotationComposer,
      $$AccountsTableCreateCompanionBuilder,
      $$AccountsTableUpdateCompanionBuilder,
      (
        AccountRow,
        BaseReferences<_$CuentariaDatabase, $AccountsTable, AccountRow>,
      ),
      AccountRow,
      PrefetchHooks Function()
    >;
typedef $$EnvelopesTableCreateCompanionBuilder =
    EnvelopesCompanion Function({
      required String id,
      required String name,
      required String role,
      required bool isArchived,
      required int updatedAt,
      Value<String?> meta,
      Value<int> rowid,
    });
typedef $$EnvelopesTableUpdateCompanionBuilder =
    EnvelopesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> role,
      Value<bool> isArchived,
      Value<int> updatedAt,
      Value<String?> meta,
      Value<int> rowid,
    });

class $$EnvelopesTableFilterComposer
    extends Composer<_$CuentariaDatabase, $EnvelopesTable> {
  $$EnvelopesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get meta => $composableBuilder(
    column: $table.meta,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EnvelopesTableOrderingComposer
    extends Composer<_$CuentariaDatabase, $EnvelopesTable> {
  $$EnvelopesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get meta => $composableBuilder(
    column: $table.meta,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EnvelopesTableAnnotationComposer
    extends Composer<_$CuentariaDatabase, $EnvelopesTable> {
  $$EnvelopesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get meta =>
      $composableBuilder(column: $table.meta, builder: (column) => column);
}

class $$EnvelopesTableTableManager
    extends
        RootTableManager<
          _$CuentariaDatabase,
          $EnvelopesTable,
          EnvelopeRow,
          $$EnvelopesTableFilterComposer,
          $$EnvelopesTableOrderingComposer,
          $$EnvelopesTableAnnotationComposer,
          $$EnvelopesTableCreateCompanionBuilder,
          $$EnvelopesTableUpdateCompanionBuilder,
          (
            EnvelopeRow,
            BaseReferences<_$CuentariaDatabase, $EnvelopesTable, EnvelopeRow>,
          ),
          EnvelopeRow,
          PrefetchHooks Function()
        > {
  $$EnvelopesTableTableManager(_$CuentariaDatabase db, $EnvelopesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$EnvelopesTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$EnvelopesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$EnvelopesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<bool> isArchived = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<String?> meta = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EnvelopesCompanion(
                id: id,
                name: name,
                role: role,
                isArchived: isArchived,
                updatedAt: updatedAt,
                meta: meta,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String role,
                required bool isArchived,
                required int updatedAt,
                Value<String?> meta = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EnvelopesCompanion.insert(
                id: id,
                name: name,
                role: role,
                isArchived: isArchived,
                updatedAt: updatedAt,
                meta: meta,
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

typedef $$EnvelopesTableProcessedTableManager =
    ProcessedTableManager<
      _$CuentariaDatabase,
      $EnvelopesTable,
      EnvelopeRow,
      $$EnvelopesTableFilterComposer,
      $$EnvelopesTableOrderingComposer,
      $$EnvelopesTableAnnotationComposer,
      $$EnvelopesTableCreateCompanionBuilder,
      $$EnvelopesTableUpdateCompanionBuilder,
      (
        EnvelopeRow,
        BaseReferences<_$CuentariaDatabase, $EnvelopesTable, EnvelopeRow>,
      ),
      EnvelopeRow,
      PrefetchHooks Function()
    >;
typedef $$CascadeConfigTableCreateCompanionBuilder =
    CascadeConfigCompanion Function({
      required String rowId,
      required String steps,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$CascadeConfigTableUpdateCompanionBuilder =
    CascadeConfigCompanion Function({
      Value<String> rowId,
      Value<String> steps,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $$CascadeConfigTableFilterComposer
    extends Composer<_$CuentariaDatabase, $CascadeConfigTable> {
  $$CascadeConfigTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get rowId => $composableBuilder(
    column: $table.rowId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get steps => $composableBuilder(
    column: $table.steps,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CascadeConfigTableOrderingComposer
    extends Composer<_$CuentariaDatabase, $CascadeConfigTable> {
  $$CascadeConfigTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get rowId => $composableBuilder(
    column: $table.rowId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get steps => $composableBuilder(
    column: $table.steps,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CascadeConfigTableAnnotationComposer
    extends Composer<_$CuentariaDatabase, $CascadeConfigTable> {
  $$CascadeConfigTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get rowId =>
      $composableBuilder(column: $table.rowId, builder: (column) => column);

  GeneratedColumn<String> get steps =>
      $composableBuilder(column: $table.steps, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CascadeConfigTableTableManager
    extends
        RootTableManager<
          _$CuentariaDatabase,
          $CascadeConfigTable,
          CascadeConfigRow,
          $$CascadeConfigTableFilterComposer,
          $$CascadeConfigTableOrderingComposer,
          $$CascadeConfigTableAnnotationComposer,
          $$CascadeConfigTableCreateCompanionBuilder,
          $$CascadeConfigTableUpdateCompanionBuilder,
          (
            CascadeConfigRow,
            BaseReferences<
              _$CuentariaDatabase,
              $CascadeConfigTable,
              CascadeConfigRow
            >,
          ),
          CascadeConfigRow,
          PrefetchHooks Function()
        > {
  $$CascadeConfigTableTableManager(
    _$CuentariaDatabase db,
    $CascadeConfigTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$CascadeConfigTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () =>
                  $$CascadeConfigTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$CascadeConfigTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> rowId = const Value.absent(),
                Value<String> steps = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CascadeConfigCompanion(
                rowId: rowId,
                steps: steps,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String rowId,
                required String steps,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CascadeConfigCompanion.insert(
                rowId: rowId,
                steps: steps,
                updatedAt: updatedAt,
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

typedef $$CascadeConfigTableProcessedTableManager =
    ProcessedTableManager<
      _$CuentariaDatabase,
      $CascadeConfigTable,
      CascadeConfigRow,
      $$CascadeConfigTableFilterComposer,
      $$CascadeConfigTableOrderingComposer,
      $$CascadeConfigTableAnnotationComposer,
      $$CascadeConfigTableCreateCompanionBuilder,
      $$CascadeConfigTableUpdateCompanionBuilder,
      (
        CascadeConfigRow,
        BaseReferences<
          _$CuentariaDatabase,
          $CascadeConfigTable,
          CascadeConfigRow
        >,
      ),
      CascadeConfigRow,
      PrefetchHooks Function()
    >;
typedef $$AppMetaTableCreateCompanionBuilder =
    AppMetaCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$AppMetaTableUpdateCompanionBuilder =
    AppMetaCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$AppMetaTableFilterComposer
    extends Composer<_$CuentariaDatabase, $AppMetaTable> {
  $$AppMetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppMetaTableOrderingComposer
    extends Composer<_$CuentariaDatabase, $AppMetaTable> {
  $$AppMetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppMetaTableAnnotationComposer
    extends Composer<_$CuentariaDatabase, $AppMetaTable> {
  $$AppMetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$AppMetaTableTableManager
    extends
        RootTableManager<
          _$CuentariaDatabase,
          $AppMetaTable,
          AppMetaRow,
          $$AppMetaTableFilterComposer,
          $$AppMetaTableOrderingComposer,
          $$AppMetaTableAnnotationComposer,
          $$AppMetaTableCreateCompanionBuilder,
          $$AppMetaTableUpdateCompanionBuilder,
          (
            AppMetaRow,
            BaseReferences<_$CuentariaDatabase, $AppMetaTable, AppMetaRow>,
          ),
          AppMetaRow,
          PrefetchHooks Function()
        > {
  $$AppMetaTableTableManager(_$CuentariaDatabase db, $AppMetaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$AppMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$AppMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$AppMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppMetaCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) =>
                  AppMetaCompanion.insert(key: key, value: value, rowid: rowid),
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

typedef $$AppMetaTableProcessedTableManager =
    ProcessedTableManager<
      _$CuentariaDatabase,
      $AppMetaTable,
      AppMetaRow,
      $$AppMetaTableFilterComposer,
      $$AppMetaTableOrderingComposer,
      $$AppMetaTableAnnotationComposer,
      $$AppMetaTableCreateCompanionBuilder,
      $$AppMetaTableUpdateCompanionBuilder,
      (
        AppMetaRow,
        BaseReferences<_$CuentariaDatabase, $AppMetaTable, AppMetaRow>,
      ),
      AppMetaRow,
      PrefetchHooks Function()
    >;

class $CuentariaDatabaseManager {
  final _$CuentariaDatabase _db;
  $CuentariaDatabaseManager(this._db);
  $$EventsTableTableManager get events =>
      $$EventsTableTableManager(_db, _db.events);
  $$EventTargetsTableTableManager get eventTargets =>
      $$EventTargetsTableTableManager(_db, _db.eventTargets);
  $$AccountsTableTableManager get accounts =>
      $$AccountsTableTableManager(_db, _db.accounts);
  $$EnvelopesTableTableManager get envelopes =>
      $$EnvelopesTableTableManager(_db, _db.envelopes);
  $$CascadeConfigTableTableManager get cascadeConfig =>
      $$CascadeConfigTableTableManager(_db, _db.cascadeConfig);
  $$AppMetaTableTableManager get appMeta =>
      $$AppMetaTableTableManager(_db, _db.appMeta);
}
