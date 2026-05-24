// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'meridian_database.dart';

// ignore_for_file: type=lint
class $StationsTable extends Stations
    with TableInfo<$StationsTable, StationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _callsignMeta = const VerificationMeta(
    'callsign',
  );
  @override
  late final GeneratedColumn<String> callsign = GeneratedColumn<String>(
    'callsign',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _symbolTableMeta = const VerificationMeta(
    'symbolTable',
  );
  @override
  late final GeneratedColumn<String> symbolTable = GeneratedColumn<String>(
    'symbol_table',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _symbolCodeMeta = const VerificationMeta(
    'symbolCode',
  );
  @override
  late final GeneratedColumn<String> symbolCode = GeneratedColumn<String>(
    'symbol_code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _commentMeta = const VerificationMeta(
    'comment',
  );
  @override
  late final GeneratedColumn<String> comment = GeneratedColumn<String>(
    'comment',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rawPacketMeta = const VerificationMeta(
    'rawPacket',
  );
  @override
  late final GeneratedColumn<String> rawPacket = GeneratedColumn<String>(
    'raw_packet',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceMeta = const VerificationMeta('device');
  @override
  late final GeneratedColumn<String> device = GeneratedColumn<String>(
    'device',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastHeardMeta = const VerificationMeta(
    'lastHeard',
  );
  @override
  late final GeneratedColumn<int> lastHeard = GeneratedColumn<int>(
    'last_heard',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<StationType, String> stationType =
      GeneratedColumn<String>(
        'station_type',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<StationType>($StationsTable.$converterstationType);
  @override
  late final GeneratedColumnWithTypeConverter<MessageCapability, String>
  messageCapability =
      GeneratedColumn<String>(
        'message_capability',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<MessageCapability>(
        $StationsTable.$convertermessageCapability,
      );
  static const VerificationMeta _capabilitiesMeta = const VerificationMeta(
    'capabilities',
  );
  @override
  late final GeneratedColumn<String> capabilities = GeneratedColumn<String>(
    'capabilities',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _latMeta = const VerificationMeta('lat');
  @override
  late final GeneratedColumn<double> lat = GeneratedColumn<double>(
    'lat',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lonMeta = const VerificationMeta('lon');
  @override
  late final GeneratedColumn<double> lon = GeneratedColumn<double>(
    'lon',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    callsign,
    symbolTable,
    symbolCode,
    comment,
    rawPacket,
    device,
    lastHeard,
    stationType,
    messageCapability,
    capabilities,
    lat,
    lon,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stations';
  @override
  VerificationContext validateIntegrity(
    Insertable<StationRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('callsign')) {
      context.handle(
        _callsignMeta,
        callsign.isAcceptableOrUnknown(data['callsign']!, _callsignMeta),
      );
    } else if (isInserting) {
      context.missing(_callsignMeta);
    }
    if (data.containsKey('symbol_table')) {
      context.handle(
        _symbolTableMeta,
        symbolTable.isAcceptableOrUnknown(
          data['symbol_table']!,
          _symbolTableMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_symbolTableMeta);
    }
    if (data.containsKey('symbol_code')) {
      context.handle(
        _symbolCodeMeta,
        symbolCode.isAcceptableOrUnknown(data['symbol_code']!, _symbolCodeMeta),
      );
    } else if (isInserting) {
      context.missing(_symbolCodeMeta);
    }
    if (data.containsKey('comment')) {
      context.handle(
        _commentMeta,
        comment.isAcceptableOrUnknown(data['comment']!, _commentMeta),
      );
    } else if (isInserting) {
      context.missing(_commentMeta);
    }
    if (data.containsKey('raw_packet')) {
      context.handle(
        _rawPacketMeta,
        rawPacket.isAcceptableOrUnknown(data['raw_packet']!, _rawPacketMeta),
      );
    } else if (isInserting) {
      context.missing(_rawPacketMeta);
    }
    if (data.containsKey('device')) {
      context.handle(
        _deviceMeta,
        device.isAcceptableOrUnknown(data['device']!, _deviceMeta),
      );
    }
    if (data.containsKey('last_heard')) {
      context.handle(
        _lastHeardMeta,
        lastHeard.isAcceptableOrUnknown(data['last_heard']!, _lastHeardMeta),
      );
    } else if (isInserting) {
      context.missing(_lastHeardMeta);
    }
    if (data.containsKey('capabilities')) {
      context.handle(
        _capabilitiesMeta,
        capabilities.isAcceptableOrUnknown(
          data['capabilities']!,
          _capabilitiesMeta,
        ),
      );
    }
    if (data.containsKey('lat')) {
      context.handle(
        _latMeta,
        lat.isAcceptableOrUnknown(data['lat']!, _latMeta),
      );
    } else if (isInserting) {
      context.missing(_latMeta);
    }
    if (data.containsKey('lon')) {
      context.handle(
        _lonMeta,
        lon.isAcceptableOrUnknown(data['lon']!, _lonMeta),
      );
    } else if (isInserting) {
      context.missing(_lonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {callsign};
  @override
  StationRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StationRow(
      callsign: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}callsign'],
      )!,
      symbolTable: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}symbol_table'],
      )!,
      symbolCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}symbol_code'],
      )!,
      comment: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}comment'],
      )!,
      rawPacket: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw_packet'],
      )!,
      device: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device'],
      ),
      lastHeard: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_heard'],
      )!,
      stationType: $StationsTable.$converterstationType.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}station_type'],
        )!,
      ),
      messageCapability: $StationsTable.$convertermessageCapability.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}message_capability'],
        )!,
      ),
      capabilities: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}capabilities'],
      ),
      lat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lat'],
      )!,
      lon: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lon'],
      )!,
    );
  }

  @override
  $StationsTable createAlias(String alias) {
    return $StationsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<StationType, String, String> $converterstationType =
      const EnumNameConverter(StationType.values);
  static JsonTypeConverter2<MessageCapability, String, String>
  $convertermessageCapability = const EnumNameConverter(
    MessageCapability.values,
  );
}

class StationRow extends DataClass implements Insertable<StationRow> {
  final String callsign;
  final String symbolTable;
  final String symbolCode;
  final String comment;
  final String rawPacket;
  final String? device;
  final int lastHeard;
  final StationType stationType;
  final MessageCapability messageCapability;
  final String? capabilities;
  final double lat;
  final double lon;
  const StationRow({
    required this.callsign,
    required this.symbolTable,
    required this.symbolCode,
    required this.comment,
    required this.rawPacket,
    this.device,
    required this.lastHeard,
    required this.stationType,
    required this.messageCapability,
    this.capabilities,
    required this.lat,
    required this.lon,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['callsign'] = Variable<String>(callsign);
    map['symbol_table'] = Variable<String>(symbolTable);
    map['symbol_code'] = Variable<String>(symbolCode);
    map['comment'] = Variable<String>(comment);
    map['raw_packet'] = Variable<String>(rawPacket);
    if (!nullToAbsent || device != null) {
      map['device'] = Variable<String>(device);
    }
    map['last_heard'] = Variable<int>(lastHeard);
    {
      map['station_type'] = Variable<String>(
        $StationsTable.$converterstationType.toSql(stationType),
      );
    }
    {
      map['message_capability'] = Variable<String>(
        $StationsTable.$convertermessageCapability.toSql(messageCapability),
      );
    }
    if (!nullToAbsent || capabilities != null) {
      map['capabilities'] = Variable<String>(capabilities);
    }
    map['lat'] = Variable<double>(lat);
    map['lon'] = Variable<double>(lon);
    return map;
  }

  StationsCompanion toCompanion(bool nullToAbsent) {
    return StationsCompanion(
      callsign: Value(callsign),
      symbolTable: Value(symbolTable),
      symbolCode: Value(symbolCode),
      comment: Value(comment),
      rawPacket: Value(rawPacket),
      device: device == null && nullToAbsent
          ? const Value.absent()
          : Value(device),
      lastHeard: Value(lastHeard),
      stationType: Value(stationType),
      messageCapability: Value(messageCapability),
      capabilities: capabilities == null && nullToAbsent
          ? const Value.absent()
          : Value(capabilities),
      lat: Value(lat),
      lon: Value(lon),
    );
  }

  factory StationRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StationRow(
      callsign: serializer.fromJson<String>(json['callsign']),
      symbolTable: serializer.fromJson<String>(json['symbolTable']),
      symbolCode: serializer.fromJson<String>(json['symbolCode']),
      comment: serializer.fromJson<String>(json['comment']),
      rawPacket: serializer.fromJson<String>(json['rawPacket']),
      device: serializer.fromJson<String?>(json['device']),
      lastHeard: serializer.fromJson<int>(json['lastHeard']),
      stationType: $StationsTable.$converterstationType.fromJson(
        serializer.fromJson<String>(json['stationType']),
      ),
      messageCapability: $StationsTable.$convertermessageCapability.fromJson(
        serializer.fromJson<String>(json['messageCapability']),
      ),
      capabilities: serializer.fromJson<String?>(json['capabilities']),
      lat: serializer.fromJson<double>(json['lat']),
      lon: serializer.fromJson<double>(json['lon']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'callsign': serializer.toJson<String>(callsign),
      'symbolTable': serializer.toJson<String>(symbolTable),
      'symbolCode': serializer.toJson<String>(symbolCode),
      'comment': serializer.toJson<String>(comment),
      'rawPacket': serializer.toJson<String>(rawPacket),
      'device': serializer.toJson<String?>(device),
      'lastHeard': serializer.toJson<int>(lastHeard),
      'stationType': serializer.toJson<String>(
        $StationsTable.$converterstationType.toJson(stationType),
      ),
      'messageCapability': serializer.toJson<String>(
        $StationsTable.$convertermessageCapability.toJson(messageCapability),
      ),
      'capabilities': serializer.toJson<String?>(capabilities),
      'lat': serializer.toJson<double>(lat),
      'lon': serializer.toJson<double>(lon),
    };
  }

  StationRow copyWith({
    String? callsign,
    String? symbolTable,
    String? symbolCode,
    String? comment,
    String? rawPacket,
    Value<String?> device = const Value.absent(),
    int? lastHeard,
    StationType? stationType,
    MessageCapability? messageCapability,
    Value<String?> capabilities = const Value.absent(),
    double? lat,
    double? lon,
  }) => StationRow(
    callsign: callsign ?? this.callsign,
    symbolTable: symbolTable ?? this.symbolTable,
    symbolCode: symbolCode ?? this.symbolCode,
    comment: comment ?? this.comment,
    rawPacket: rawPacket ?? this.rawPacket,
    device: device.present ? device.value : this.device,
    lastHeard: lastHeard ?? this.lastHeard,
    stationType: stationType ?? this.stationType,
    messageCapability: messageCapability ?? this.messageCapability,
    capabilities: capabilities.present ? capabilities.value : this.capabilities,
    lat: lat ?? this.lat,
    lon: lon ?? this.lon,
  );
  StationRow copyWithCompanion(StationsCompanion data) {
    return StationRow(
      callsign: data.callsign.present ? data.callsign.value : this.callsign,
      symbolTable: data.symbolTable.present
          ? data.symbolTable.value
          : this.symbolTable,
      symbolCode: data.symbolCode.present
          ? data.symbolCode.value
          : this.symbolCode,
      comment: data.comment.present ? data.comment.value : this.comment,
      rawPacket: data.rawPacket.present ? data.rawPacket.value : this.rawPacket,
      device: data.device.present ? data.device.value : this.device,
      lastHeard: data.lastHeard.present ? data.lastHeard.value : this.lastHeard,
      stationType: data.stationType.present
          ? data.stationType.value
          : this.stationType,
      messageCapability: data.messageCapability.present
          ? data.messageCapability.value
          : this.messageCapability,
      capabilities: data.capabilities.present
          ? data.capabilities.value
          : this.capabilities,
      lat: data.lat.present ? data.lat.value : this.lat,
      lon: data.lon.present ? data.lon.value : this.lon,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StationRow(')
          ..write('callsign: $callsign, ')
          ..write('symbolTable: $symbolTable, ')
          ..write('symbolCode: $symbolCode, ')
          ..write('comment: $comment, ')
          ..write('rawPacket: $rawPacket, ')
          ..write('device: $device, ')
          ..write('lastHeard: $lastHeard, ')
          ..write('stationType: $stationType, ')
          ..write('messageCapability: $messageCapability, ')
          ..write('capabilities: $capabilities, ')
          ..write('lat: $lat, ')
          ..write('lon: $lon')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    callsign,
    symbolTable,
    symbolCode,
    comment,
    rawPacket,
    device,
    lastHeard,
    stationType,
    messageCapability,
    capabilities,
    lat,
    lon,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StationRow &&
          other.callsign == this.callsign &&
          other.symbolTable == this.symbolTable &&
          other.symbolCode == this.symbolCode &&
          other.comment == this.comment &&
          other.rawPacket == this.rawPacket &&
          other.device == this.device &&
          other.lastHeard == this.lastHeard &&
          other.stationType == this.stationType &&
          other.messageCapability == this.messageCapability &&
          other.capabilities == this.capabilities &&
          other.lat == this.lat &&
          other.lon == this.lon);
}

class StationsCompanion extends UpdateCompanion<StationRow> {
  final Value<String> callsign;
  final Value<String> symbolTable;
  final Value<String> symbolCode;
  final Value<String> comment;
  final Value<String> rawPacket;
  final Value<String?> device;
  final Value<int> lastHeard;
  final Value<StationType> stationType;
  final Value<MessageCapability> messageCapability;
  final Value<String?> capabilities;
  final Value<double> lat;
  final Value<double> lon;
  final Value<int> rowid;
  const StationsCompanion({
    this.callsign = const Value.absent(),
    this.symbolTable = const Value.absent(),
    this.symbolCode = const Value.absent(),
    this.comment = const Value.absent(),
    this.rawPacket = const Value.absent(),
    this.device = const Value.absent(),
    this.lastHeard = const Value.absent(),
    this.stationType = const Value.absent(),
    this.messageCapability = const Value.absent(),
    this.capabilities = const Value.absent(),
    this.lat = const Value.absent(),
    this.lon = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StationsCompanion.insert({
    required String callsign,
    required String symbolTable,
    required String symbolCode,
    required String comment,
    required String rawPacket,
    this.device = const Value.absent(),
    required int lastHeard,
    required StationType stationType,
    required MessageCapability messageCapability,
    this.capabilities = const Value.absent(),
    required double lat,
    required double lon,
    this.rowid = const Value.absent(),
  }) : callsign = Value(callsign),
       symbolTable = Value(symbolTable),
       symbolCode = Value(symbolCode),
       comment = Value(comment),
       rawPacket = Value(rawPacket),
       lastHeard = Value(lastHeard),
       stationType = Value(stationType),
       messageCapability = Value(messageCapability),
       lat = Value(lat),
       lon = Value(lon);
  static Insertable<StationRow> custom({
    Expression<String>? callsign,
    Expression<String>? symbolTable,
    Expression<String>? symbolCode,
    Expression<String>? comment,
    Expression<String>? rawPacket,
    Expression<String>? device,
    Expression<int>? lastHeard,
    Expression<String>? stationType,
    Expression<String>? messageCapability,
    Expression<String>? capabilities,
    Expression<double>? lat,
    Expression<double>? lon,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (callsign != null) 'callsign': callsign,
      if (symbolTable != null) 'symbol_table': symbolTable,
      if (symbolCode != null) 'symbol_code': symbolCode,
      if (comment != null) 'comment': comment,
      if (rawPacket != null) 'raw_packet': rawPacket,
      if (device != null) 'device': device,
      if (lastHeard != null) 'last_heard': lastHeard,
      if (stationType != null) 'station_type': stationType,
      if (messageCapability != null) 'message_capability': messageCapability,
      if (capabilities != null) 'capabilities': capabilities,
      if (lat != null) 'lat': lat,
      if (lon != null) 'lon': lon,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StationsCompanion copyWith({
    Value<String>? callsign,
    Value<String>? symbolTable,
    Value<String>? symbolCode,
    Value<String>? comment,
    Value<String>? rawPacket,
    Value<String?>? device,
    Value<int>? lastHeard,
    Value<StationType>? stationType,
    Value<MessageCapability>? messageCapability,
    Value<String?>? capabilities,
    Value<double>? lat,
    Value<double>? lon,
    Value<int>? rowid,
  }) {
    return StationsCompanion(
      callsign: callsign ?? this.callsign,
      symbolTable: symbolTable ?? this.symbolTable,
      symbolCode: symbolCode ?? this.symbolCode,
      comment: comment ?? this.comment,
      rawPacket: rawPacket ?? this.rawPacket,
      device: device ?? this.device,
      lastHeard: lastHeard ?? this.lastHeard,
      stationType: stationType ?? this.stationType,
      messageCapability: messageCapability ?? this.messageCapability,
      capabilities: capabilities ?? this.capabilities,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (callsign.present) {
      map['callsign'] = Variable<String>(callsign.value);
    }
    if (symbolTable.present) {
      map['symbol_table'] = Variable<String>(symbolTable.value);
    }
    if (symbolCode.present) {
      map['symbol_code'] = Variable<String>(symbolCode.value);
    }
    if (comment.present) {
      map['comment'] = Variable<String>(comment.value);
    }
    if (rawPacket.present) {
      map['raw_packet'] = Variable<String>(rawPacket.value);
    }
    if (device.present) {
      map['device'] = Variable<String>(device.value);
    }
    if (lastHeard.present) {
      map['last_heard'] = Variable<int>(lastHeard.value);
    }
    if (stationType.present) {
      map['station_type'] = Variable<String>(
        $StationsTable.$converterstationType.toSql(stationType.value),
      );
    }
    if (messageCapability.present) {
      map['message_capability'] = Variable<String>(
        $StationsTable.$convertermessageCapability.toSql(
          messageCapability.value,
        ),
      );
    }
    if (capabilities.present) {
      map['capabilities'] = Variable<String>(capabilities.value);
    }
    if (lat.present) {
      map['lat'] = Variable<double>(lat.value);
    }
    if (lon.present) {
      map['lon'] = Variable<double>(lon.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StationsCompanion(')
          ..write('callsign: $callsign, ')
          ..write('symbolTable: $symbolTable, ')
          ..write('symbolCode: $symbolCode, ')
          ..write('comment: $comment, ')
          ..write('rawPacket: $rawPacket, ')
          ..write('device: $device, ')
          ..write('lastHeard: $lastHeard, ')
          ..write('stationType: $stationType, ')
          ..write('messageCapability: $messageCapability, ')
          ..write('capabilities: $capabilities, ')
          ..write('lat: $lat, ')
          ..write('lon: $lon, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PositionHistoryTable extends PositionHistory
    with TableInfo<$PositionHistoryTable, PositionHistoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PositionHistoryTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _callsignMeta = const VerificationMeta(
    'callsign',
  );
  @override
  late final GeneratedColumn<String> callsign = GeneratedColumn<String>(
    'callsign',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES stations (callsign) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<int> timestamp = GeneratedColumn<int>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    callsign,
    latitude,
    longitude,
    timestamp,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'position_history';
  @override
  VerificationContext validateIntegrity(
    Insertable<PositionHistoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('callsign')) {
      context.handle(
        _callsignMeta,
        callsign.isAcceptableOrUnknown(data['callsign']!, _callsignMeta),
      );
    } else if (isInserting) {
      context.missing(_callsignMeta);
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_latitudeMeta);
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_longitudeMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PositionHistoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PositionHistoryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      callsign: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}callsign'],
      )!,
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      )!,
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}timestamp'],
      )!,
    );
  }

  @override
  $PositionHistoryTable createAlias(String alias) {
    return $PositionHistoryTable(attachedDatabase, alias);
  }
}

class PositionHistoryRow extends DataClass
    implements Insertable<PositionHistoryRow> {
  final int id;
  final String callsign;
  final double latitude;
  final double longitude;
  final int timestamp;
  const PositionHistoryRow({
    required this.id,
    required this.callsign,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['callsign'] = Variable<String>(callsign);
    map['latitude'] = Variable<double>(latitude);
    map['longitude'] = Variable<double>(longitude);
    map['timestamp'] = Variable<int>(timestamp);
    return map;
  }

  PositionHistoryCompanion toCompanion(bool nullToAbsent) {
    return PositionHistoryCompanion(
      id: Value(id),
      callsign: Value(callsign),
      latitude: Value(latitude),
      longitude: Value(longitude),
      timestamp: Value(timestamp),
    );
  }

  factory PositionHistoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PositionHistoryRow(
      id: serializer.fromJson<int>(json['id']),
      callsign: serializer.fromJson<String>(json['callsign']),
      latitude: serializer.fromJson<double>(json['latitude']),
      longitude: serializer.fromJson<double>(json['longitude']),
      timestamp: serializer.fromJson<int>(json['timestamp']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'callsign': serializer.toJson<String>(callsign),
      'latitude': serializer.toJson<double>(latitude),
      'longitude': serializer.toJson<double>(longitude),
      'timestamp': serializer.toJson<int>(timestamp),
    };
  }

  PositionHistoryRow copyWith({
    int? id,
    String? callsign,
    double? latitude,
    double? longitude,
    int? timestamp,
  }) => PositionHistoryRow(
    id: id ?? this.id,
    callsign: callsign ?? this.callsign,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    timestamp: timestamp ?? this.timestamp,
  );
  PositionHistoryRow copyWithCompanion(PositionHistoryCompanion data) {
    return PositionHistoryRow(
      id: data.id.present ? data.id.value : this.id,
      callsign: data.callsign.present ? data.callsign.value : this.callsign,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PositionHistoryRow(')
          ..write('id: $id, ')
          ..write('callsign: $callsign, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('timestamp: $timestamp')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, callsign, latitude, longitude, timestamp);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PositionHistoryRow &&
          other.id == this.id &&
          other.callsign == this.callsign &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.timestamp == this.timestamp);
}

class PositionHistoryCompanion extends UpdateCompanion<PositionHistoryRow> {
  final Value<int> id;
  final Value<String> callsign;
  final Value<double> latitude;
  final Value<double> longitude;
  final Value<int> timestamp;
  const PositionHistoryCompanion({
    this.id = const Value.absent(),
    this.callsign = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.timestamp = const Value.absent(),
  });
  PositionHistoryCompanion.insert({
    this.id = const Value.absent(),
    required String callsign,
    required double latitude,
    required double longitude,
    required int timestamp,
  }) : callsign = Value(callsign),
       latitude = Value(latitude),
       longitude = Value(longitude),
       timestamp = Value(timestamp);
  static Insertable<PositionHistoryRow> custom({
    Expression<int>? id,
    Expression<String>? callsign,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<int>? timestamp,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (callsign != null) 'callsign': callsign,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (timestamp != null) 'timestamp': timestamp,
    });
  }

  PositionHistoryCompanion copyWith({
    Value<int>? id,
    Value<String>? callsign,
    Value<double>? latitude,
    Value<double>? longitude,
    Value<int>? timestamp,
  }) {
    return PositionHistoryCompanion(
      id: id ?? this.id,
      callsign: callsign ?? this.callsign,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (callsign.present) {
      map['callsign'] = Variable<String>(callsign.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<int>(timestamp.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PositionHistoryCompanion(')
          ..write('id: $id, ')
          ..write('callsign: $callsign, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('timestamp: $timestamp')
          ..write(')'))
        .toString();
  }
}

class $PacketsTable extends Packets with TableInfo<$PacketsTable, PacketRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PacketsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _rawLineMeta = const VerificationMeta(
    'rawLine',
  );
  @override
  late final GeneratedColumn<String> rawLine = GeneratedColumn<String>(
    'raw_line',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<PacketTypeTag, String>
  packetType = GeneratedColumn<String>(
    'packet_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<PacketTypeTag>($PacketsTable.$converterpacketType);
  static const VerificationMeta _sourceCallsignMeta = const VerificationMeta(
    'sourceCallsign',
  );
  @override
  late final GeneratedColumn<String> sourceCallsign = GeneratedColumn<String>(
    'source_callsign',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _destinationMeta = const VerificationMeta(
    'destination',
  );
  @override
  late final GeneratedColumn<String> destination = GeneratedColumn<String>(
    'destination',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _receivedAtMeta = const VerificationMeta(
    'receivedAt',
  );
  @override
  late final GeneratedColumn<int> receivedAt = GeneratedColumn<int>(
    'received_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isOutgoingMeta = const VerificationMeta(
    'isOutgoing',
  );
  @override
  late final GeneratedColumn<bool> isOutgoing = GeneratedColumn<bool>(
    'is_outgoing',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_outgoing" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  late final GeneratedColumnWithTypeConverter<PacketSource, String>
  sourceChannel = GeneratedColumn<String>(
    'source_channel',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<PacketSource>($PacketsTable.$convertersourceChannel);
  @override
  List<GeneratedColumn> get $columns => [
    id,
    rawLine,
    packetType,
    sourceCallsign,
    destination,
    receivedAt,
    isOutgoing,
    sourceChannel,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'packets';
  @override
  VerificationContext validateIntegrity(
    Insertable<PacketRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('raw_line')) {
      context.handle(
        _rawLineMeta,
        rawLine.isAcceptableOrUnknown(data['raw_line']!, _rawLineMeta),
      );
    } else if (isInserting) {
      context.missing(_rawLineMeta);
    }
    if (data.containsKey('source_callsign')) {
      context.handle(
        _sourceCallsignMeta,
        sourceCallsign.isAcceptableOrUnknown(
          data['source_callsign']!,
          _sourceCallsignMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sourceCallsignMeta);
    }
    if (data.containsKey('destination')) {
      context.handle(
        _destinationMeta,
        destination.isAcceptableOrUnknown(
          data['destination']!,
          _destinationMeta,
        ),
      );
    }
    if (data.containsKey('received_at')) {
      context.handle(
        _receivedAtMeta,
        receivedAt.isAcceptableOrUnknown(data['received_at']!, _receivedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_receivedAtMeta);
    }
    if (data.containsKey('is_outgoing')) {
      context.handle(
        _isOutgoingMeta,
        isOutgoing.isAcceptableOrUnknown(data['is_outgoing']!, _isOutgoingMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PacketRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PacketRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      rawLine: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw_line'],
      )!,
      packetType: $PacketsTable.$converterpacketType.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}packet_type'],
        )!,
      ),
      sourceCallsign: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_callsign'],
      )!,
      destination: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}destination'],
      ),
      receivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}received_at'],
      )!,
      isOutgoing: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_outgoing'],
      )!,
      sourceChannel: $PacketsTable.$convertersourceChannel.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}source_channel'],
        )!,
      ),
    );
  }

  @override
  $PacketsTable createAlias(String alias) {
    return $PacketsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<PacketTypeTag, String, String>
  $converterpacketType = const EnumNameConverter(PacketTypeTag.values);
  static JsonTypeConverter2<PacketSource, String, String>
  $convertersourceChannel = const EnumNameConverter(PacketSource.values);
}

class PacketRow extends DataClass implements Insertable<PacketRow> {
  final int id;
  final String rawLine;
  final PacketTypeTag packetType;
  final String sourceCallsign;
  final String? destination;
  final int receivedAt;
  final bool isOutgoing;
  final PacketSource sourceChannel;
  const PacketRow({
    required this.id,
    required this.rawLine,
    required this.packetType,
    required this.sourceCallsign,
    this.destination,
    required this.receivedAt,
    required this.isOutgoing,
    required this.sourceChannel,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['raw_line'] = Variable<String>(rawLine);
    {
      map['packet_type'] = Variable<String>(
        $PacketsTable.$converterpacketType.toSql(packetType),
      );
    }
    map['source_callsign'] = Variable<String>(sourceCallsign);
    if (!nullToAbsent || destination != null) {
      map['destination'] = Variable<String>(destination);
    }
    map['received_at'] = Variable<int>(receivedAt);
    map['is_outgoing'] = Variable<bool>(isOutgoing);
    {
      map['source_channel'] = Variable<String>(
        $PacketsTable.$convertersourceChannel.toSql(sourceChannel),
      );
    }
    return map;
  }

  PacketsCompanion toCompanion(bool nullToAbsent) {
    return PacketsCompanion(
      id: Value(id),
      rawLine: Value(rawLine),
      packetType: Value(packetType),
      sourceCallsign: Value(sourceCallsign),
      destination: destination == null && nullToAbsent
          ? const Value.absent()
          : Value(destination),
      receivedAt: Value(receivedAt),
      isOutgoing: Value(isOutgoing),
      sourceChannel: Value(sourceChannel),
    );
  }

  factory PacketRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PacketRow(
      id: serializer.fromJson<int>(json['id']),
      rawLine: serializer.fromJson<String>(json['rawLine']),
      packetType: $PacketsTable.$converterpacketType.fromJson(
        serializer.fromJson<String>(json['packetType']),
      ),
      sourceCallsign: serializer.fromJson<String>(json['sourceCallsign']),
      destination: serializer.fromJson<String?>(json['destination']),
      receivedAt: serializer.fromJson<int>(json['receivedAt']),
      isOutgoing: serializer.fromJson<bool>(json['isOutgoing']),
      sourceChannel: $PacketsTable.$convertersourceChannel.fromJson(
        serializer.fromJson<String>(json['sourceChannel']),
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'rawLine': serializer.toJson<String>(rawLine),
      'packetType': serializer.toJson<String>(
        $PacketsTable.$converterpacketType.toJson(packetType),
      ),
      'sourceCallsign': serializer.toJson<String>(sourceCallsign),
      'destination': serializer.toJson<String?>(destination),
      'receivedAt': serializer.toJson<int>(receivedAt),
      'isOutgoing': serializer.toJson<bool>(isOutgoing),
      'sourceChannel': serializer.toJson<String>(
        $PacketsTable.$convertersourceChannel.toJson(sourceChannel),
      ),
    };
  }

  PacketRow copyWith({
    int? id,
    String? rawLine,
    PacketTypeTag? packetType,
    String? sourceCallsign,
    Value<String?> destination = const Value.absent(),
    int? receivedAt,
    bool? isOutgoing,
    PacketSource? sourceChannel,
  }) => PacketRow(
    id: id ?? this.id,
    rawLine: rawLine ?? this.rawLine,
    packetType: packetType ?? this.packetType,
    sourceCallsign: sourceCallsign ?? this.sourceCallsign,
    destination: destination.present ? destination.value : this.destination,
    receivedAt: receivedAt ?? this.receivedAt,
    isOutgoing: isOutgoing ?? this.isOutgoing,
    sourceChannel: sourceChannel ?? this.sourceChannel,
  );
  PacketRow copyWithCompanion(PacketsCompanion data) {
    return PacketRow(
      id: data.id.present ? data.id.value : this.id,
      rawLine: data.rawLine.present ? data.rawLine.value : this.rawLine,
      packetType: data.packetType.present
          ? data.packetType.value
          : this.packetType,
      sourceCallsign: data.sourceCallsign.present
          ? data.sourceCallsign.value
          : this.sourceCallsign,
      destination: data.destination.present
          ? data.destination.value
          : this.destination,
      receivedAt: data.receivedAt.present
          ? data.receivedAt.value
          : this.receivedAt,
      isOutgoing: data.isOutgoing.present
          ? data.isOutgoing.value
          : this.isOutgoing,
      sourceChannel: data.sourceChannel.present
          ? data.sourceChannel.value
          : this.sourceChannel,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PacketRow(')
          ..write('id: $id, ')
          ..write('rawLine: $rawLine, ')
          ..write('packetType: $packetType, ')
          ..write('sourceCallsign: $sourceCallsign, ')
          ..write('destination: $destination, ')
          ..write('receivedAt: $receivedAt, ')
          ..write('isOutgoing: $isOutgoing, ')
          ..write('sourceChannel: $sourceChannel')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    rawLine,
    packetType,
    sourceCallsign,
    destination,
    receivedAt,
    isOutgoing,
    sourceChannel,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PacketRow &&
          other.id == this.id &&
          other.rawLine == this.rawLine &&
          other.packetType == this.packetType &&
          other.sourceCallsign == this.sourceCallsign &&
          other.destination == this.destination &&
          other.receivedAt == this.receivedAt &&
          other.isOutgoing == this.isOutgoing &&
          other.sourceChannel == this.sourceChannel);
}

class PacketsCompanion extends UpdateCompanion<PacketRow> {
  final Value<int> id;
  final Value<String> rawLine;
  final Value<PacketTypeTag> packetType;
  final Value<String> sourceCallsign;
  final Value<String?> destination;
  final Value<int> receivedAt;
  final Value<bool> isOutgoing;
  final Value<PacketSource> sourceChannel;
  const PacketsCompanion({
    this.id = const Value.absent(),
    this.rawLine = const Value.absent(),
    this.packetType = const Value.absent(),
    this.sourceCallsign = const Value.absent(),
    this.destination = const Value.absent(),
    this.receivedAt = const Value.absent(),
    this.isOutgoing = const Value.absent(),
    this.sourceChannel = const Value.absent(),
  });
  PacketsCompanion.insert({
    this.id = const Value.absent(),
    required String rawLine,
    required PacketTypeTag packetType,
    required String sourceCallsign,
    this.destination = const Value.absent(),
    required int receivedAt,
    this.isOutgoing = const Value.absent(),
    required PacketSource sourceChannel,
  }) : rawLine = Value(rawLine),
       packetType = Value(packetType),
       sourceCallsign = Value(sourceCallsign),
       receivedAt = Value(receivedAt),
       sourceChannel = Value(sourceChannel);
  static Insertable<PacketRow> custom({
    Expression<int>? id,
    Expression<String>? rawLine,
    Expression<String>? packetType,
    Expression<String>? sourceCallsign,
    Expression<String>? destination,
    Expression<int>? receivedAt,
    Expression<bool>? isOutgoing,
    Expression<String>? sourceChannel,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (rawLine != null) 'raw_line': rawLine,
      if (packetType != null) 'packet_type': packetType,
      if (sourceCallsign != null) 'source_callsign': sourceCallsign,
      if (destination != null) 'destination': destination,
      if (receivedAt != null) 'received_at': receivedAt,
      if (isOutgoing != null) 'is_outgoing': isOutgoing,
      if (sourceChannel != null) 'source_channel': sourceChannel,
    });
  }

  PacketsCompanion copyWith({
    Value<int>? id,
    Value<String>? rawLine,
    Value<PacketTypeTag>? packetType,
    Value<String>? sourceCallsign,
    Value<String?>? destination,
    Value<int>? receivedAt,
    Value<bool>? isOutgoing,
    Value<PacketSource>? sourceChannel,
  }) {
    return PacketsCompanion(
      id: id ?? this.id,
      rawLine: rawLine ?? this.rawLine,
      packetType: packetType ?? this.packetType,
      sourceCallsign: sourceCallsign ?? this.sourceCallsign,
      destination: destination ?? this.destination,
      receivedAt: receivedAt ?? this.receivedAt,
      isOutgoing: isOutgoing ?? this.isOutgoing,
      sourceChannel: sourceChannel ?? this.sourceChannel,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (rawLine.present) {
      map['raw_line'] = Variable<String>(rawLine.value);
    }
    if (packetType.present) {
      map['packet_type'] = Variable<String>(
        $PacketsTable.$converterpacketType.toSql(packetType.value),
      );
    }
    if (sourceCallsign.present) {
      map['source_callsign'] = Variable<String>(sourceCallsign.value);
    }
    if (destination.present) {
      map['destination'] = Variable<String>(destination.value);
    }
    if (receivedAt.present) {
      map['received_at'] = Variable<int>(receivedAt.value);
    }
    if (isOutgoing.present) {
      map['is_outgoing'] = Variable<bool>(isOutgoing.value);
    }
    if (sourceChannel.present) {
      map['source_channel'] = Variable<String>(
        $PacketsTable.$convertersourceChannel.toSql(sourceChannel.value),
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PacketsCompanion(')
          ..write('id: $id, ')
          ..write('rawLine: $rawLine, ')
          ..write('packetType: $packetType, ')
          ..write('sourceCallsign: $sourceCallsign, ')
          ..write('destination: $destination, ')
          ..write('receivedAt: $receivedAt, ')
          ..write('isOutgoing: $isOutgoing, ')
          ..write('sourceChannel: $sourceChannel')
          ..write(')'))
        .toString();
  }
}

class $ConversationsTable extends Conversations
    with TableInfo<$ConversationsTable, ConversationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConversationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _peerCallsignMeta = const VerificationMeta(
    'peerCallsign',
  );
  @override
  late final GeneratedColumn<String> peerCallsign = GeneratedColumn<String>(
    'peer_callsign',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastMessageAtMeta = const VerificationMeta(
    'lastMessageAt',
  );
  @override
  late final GeneratedColumn<int> lastMessageAt = GeneratedColumn<int>(
    'last_message_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _unreadCountMeta = const VerificationMeta(
    'unreadCount',
  );
  @override
  late final GeneratedColumn<int> unreadCount = GeneratedColumn<int>(
    'unread_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    peerCallsign,
    lastMessageAt,
    unreadCount,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'conversations';
  @override
  VerificationContext validateIntegrity(
    Insertable<ConversationRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('peer_callsign')) {
      context.handle(
        _peerCallsignMeta,
        peerCallsign.isAcceptableOrUnknown(
          data['peer_callsign']!,
          _peerCallsignMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_peerCallsignMeta);
    }
    if (data.containsKey('last_message_at')) {
      context.handle(
        _lastMessageAtMeta,
        lastMessageAt.isAcceptableOrUnknown(
          data['last_message_at']!,
          _lastMessageAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastMessageAtMeta);
    }
    if (data.containsKey('unread_count')) {
      context.handle(
        _unreadCountMeta,
        unreadCount.isAcceptableOrUnknown(
          data['unread_count']!,
          _unreadCountMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {peerCallsign};
  @override
  ConversationRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ConversationRow(
      peerCallsign: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_callsign'],
      )!,
      lastMessageAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_message_at'],
      )!,
      unreadCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unread_count'],
      )!,
    );
  }

  @override
  $ConversationsTable createAlias(String alias) {
    return $ConversationsTable(attachedDatabase, alias);
  }
}

class ConversationRow extends DataClass implements Insertable<ConversationRow> {
  final String peerCallsign;
  final int lastMessageAt;
  final int unreadCount;
  const ConversationRow({
    required this.peerCallsign,
    required this.lastMessageAt,
    required this.unreadCount,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['peer_callsign'] = Variable<String>(peerCallsign);
    map['last_message_at'] = Variable<int>(lastMessageAt);
    map['unread_count'] = Variable<int>(unreadCount);
    return map;
  }

  ConversationsCompanion toCompanion(bool nullToAbsent) {
    return ConversationsCompanion(
      peerCallsign: Value(peerCallsign),
      lastMessageAt: Value(lastMessageAt),
      unreadCount: Value(unreadCount),
    );
  }

  factory ConversationRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ConversationRow(
      peerCallsign: serializer.fromJson<String>(json['peerCallsign']),
      lastMessageAt: serializer.fromJson<int>(json['lastMessageAt']),
      unreadCount: serializer.fromJson<int>(json['unreadCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'peerCallsign': serializer.toJson<String>(peerCallsign),
      'lastMessageAt': serializer.toJson<int>(lastMessageAt),
      'unreadCount': serializer.toJson<int>(unreadCount),
    };
  }

  ConversationRow copyWith({
    String? peerCallsign,
    int? lastMessageAt,
    int? unreadCount,
  }) => ConversationRow(
    peerCallsign: peerCallsign ?? this.peerCallsign,
    lastMessageAt: lastMessageAt ?? this.lastMessageAt,
    unreadCount: unreadCount ?? this.unreadCount,
  );
  ConversationRow copyWithCompanion(ConversationsCompanion data) {
    return ConversationRow(
      peerCallsign: data.peerCallsign.present
          ? data.peerCallsign.value
          : this.peerCallsign,
      lastMessageAt: data.lastMessageAt.present
          ? data.lastMessageAt.value
          : this.lastMessageAt,
      unreadCount: data.unreadCount.present
          ? data.unreadCount.value
          : this.unreadCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ConversationRow(')
          ..write('peerCallsign: $peerCallsign, ')
          ..write('lastMessageAt: $lastMessageAt, ')
          ..write('unreadCount: $unreadCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(peerCallsign, lastMessageAt, unreadCount);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConversationRow &&
          other.peerCallsign == this.peerCallsign &&
          other.lastMessageAt == this.lastMessageAt &&
          other.unreadCount == this.unreadCount);
}

class ConversationsCompanion extends UpdateCompanion<ConversationRow> {
  final Value<String> peerCallsign;
  final Value<int> lastMessageAt;
  final Value<int> unreadCount;
  final Value<int> rowid;
  const ConversationsCompanion({
    this.peerCallsign = const Value.absent(),
    this.lastMessageAt = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ConversationsCompanion.insert({
    required String peerCallsign,
    required int lastMessageAt,
    this.unreadCount = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : peerCallsign = Value(peerCallsign),
       lastMessageAt = Value(lastMessageAt);
  static Insertable<ConversationRow> custom({
    Expression<String>? peerCallsign,
    Expression<int>? lastMessageAt,
    Expression<int>? unreadCount,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (peerCallsign != null) 'peer_callsign': peerCallsign,
      if (lastMessageAt != null) 'last_message_at': lastMessageAt,
      if (unreadCount != null) 'unread_count': unreadCount,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ConversationsCompanion copyWith({
    Value<String>? peerCallsign,
    Value<int>? lastMessageAt,
    Value<int>? unreadCount,
    Value<int>? rowid,
  }) {
    return ConversationsCompanion(
      peerCallsign: peerCallsign ?? this.peerCallsign,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (peerCallsign.present) {
      map['peer_callsign'] = Variable<String>(peerCallsign.value);
    }
    if (lastMessageAt.present) {
      map['last_message_at'] = Variable<int>(lastMessageAt.value);
    }
    if (unreadCount.present) {
      map['unread_count'] = Variable<int>(unreadCount.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConversationsCompanion(')
          ..write('peerCallsign: $peerCallsign, ')
          ..write('lastMessageAt: $lastMessageAt, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessageEntriesTable extends MessageEntries
    with TableInfo<$MessageEntriesTable, MessageEntryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessageEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conversationPeerMeta = const VerificationMeta(
    'conversationPeer',
  );
  @override
  late final GeneratedColumn<String> conversationPeer = GeneratedColumn<String>(
    'conversation_peer',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES conversations (peer_callsign) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _fromCallsignMeta = const VerificationMeta(
    'fromCallsign',
  );
  @override
  late final GeneratedColumn<String> fromCallsign = GeneratedColumn<String>(
    'from_callsign',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addresseeMeta = const VerificationMeta(
    'addressee',
  );
  @override
  late final GeneratedColumn<String> addressee = GeneratedColumn<String>(
    'addressee',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<int> timestamp = GeneratedColumn<int>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isOutgoingMeta = const VerificationMeta(
    'isOutgoing',
  );
  @override
  late final GeneratedColumn<bool> isOutgoing = GeneratedColumn<bool>(
    'is_outgoing',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_outgoing" IN (0, 1))',
    ),
  );
  static const VerificationMeta _wireIdMeta = const VerificationMeta('wireId');
  @override
  late final GeneratedColumn<String> wireId = GeneratedColumn<String>(
    'wire_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<MessageStatus, String> status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<MessageStatus>($MessageEntriesTable.$converterstatus);
  static const VerificationMeta _retryCountMeta = const VerificationMeta(
    'retryCount',
  );
  @override
  late final GeneratedColumn<int> retryCount = GeneratedColumn<int>(
    'retry_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  late final GeneratedColumnWithTypeConverter<MessageCategory, String>
  category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<MessageCategory>($MessageEntriesTable.$convertercategory);
  static const VerificationMeta _groupNameMeta = const VerificationMeta(
    'groupName',
  );
  @override
  late final GeneratedColumn<String> groupName = GeneratedColumn<String>(
    'group_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    conversationPeer,
    fromCallsign,
    addressee,
    body,
    timestamp,
    isOutgoing,
    wireId,
    status,
    retryCount,
    category,
    groupName,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'message_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<MessageEntryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('conversation_peer')) {
      context.handle(
        _conversationPeerMeta,
        conversationPeer.isAcceptableOrUnknown(
          data['conversation_peer']!,
          _conversationPeerMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationPeerMeta);
    }
    if (data.containsKey('from_callsign')) {
      context.handle(
        _fromCallsignMeta,
        fromCallsign.isAcceptableOrUnknown(
          data['from_callsign']!,
          _fromCallsignMeta,
        ),
      );
    }
    if (data.containsKey('addressee')) {
      context.handle(
        _addresseeMeta,
        addressee.isAcceptableOrUnknown(data['addressee']!, _addresseeMeta),
      );
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('is_outgoing')) {
      context.handle(
        _isOutgoingMeta,
        isOutgoing.isAcceptableOrUnknown(data['is_outgoing']!, _isOutgoingMeta),
      );
    } else if (isInserting) {
      context.missing(_isOutgoingMeta);
    }
    if (data.containsKey('wire_id')) {
      context.handle(
        _wireIdMeta,
        wireId.isAcceptableOrUnknown(data['wire_id']!, _wireIdMeta),
      );
    }
    if (data.containsKey('retry_count')) {
      context.handle(
        _retryCountMeta,
        retryCount.isAcceptableOrUnknown(data['retry_count']!, _retryCountMeta),
      );
    }
    if (data.containsKey('group_name')) {
      context.handle(
        _groupNameMeta,
        groupName.isAcceptableOrUnknown(data['group_name']!, _groupNameMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MessageEntryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MessageEntryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      conversationPeer: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_peer'],
      )!,
      fromCallsign: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}from_callsign'],
      ),
      addressee: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}addressee'],
      ),
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}timestamp'],
      )!,
      isOutgoing: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_outgoing'],
      )!,
      wireId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}wire_id'],
      ),
      status: $MessageEntriesTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      retryCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}retry_count'],
      )!,
      category: $MessageEntriesTable.$convertercategory.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}category'],
        )!,
      ),
      groupName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_name'],
      ),
    );
  }

  @override
  $MessageEntriesTable createAlias(String alias) {
    return $MessageEntriesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<MessageStatus, String, String> $converterstatus =
      const EnumNameConverter(MessageStatus.values);
  static JsonTypeConverter2<MessageCategory, String, String>
  $convertercategory = const EnumNameConverter(MessageCategory.values);
}

class MessageEntryRow extends DataClass implements Insertable<MessageEntryRow> {
  final String id;
  final String conversationPeer;
  final String? fromCallsign;
  final String? addressee;
  final String body;
  final int timestamp;
  final bool isOutgoing;
  final String? wireId;
  final MessageStatus status;
  final int retryCount;
  final MessageCategory category;
  final String? groupName;
  const MessageEntryRow({
    required this.id,
    required this.conversationPeer,
    this.fromCallsign,
    this.addressee,
    required this.body,
    required this.timestamp,
    required this.isOutgoing,
    this.wireId,
    required this.status,
    required this.retryCount,
    required this.category,
    this.groupName,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['conversation_peer'] = Variable<String>(conversationPeer);
    if (!nullToAbsent || fromCallsign != null) {
      map['from_callsign'] = Variable<String>(fromCallsign);
    }
    if (!nullToAbsent || addressee != null) {
      map['addressee'] = Variable<String>(addressee);
    }
    map['body'] = Variable<String>(body);
    map['timestamp'] = Variable<int>(timestamp);
    map['is_outgoing'] = Variable<bool>(isOutgoing);
    if (!nullToAbsent || wireId != null) {
      map['wire_id'] = Variable<String>(wireId);
    }
    {
      map['status'] = Variable<String>(
        $MessageEntriesTable.$converterstatus.toSql(status),
      );
    }
    map['retry_count'] = Variable<int>(retryCount);
    {
      map['category'] = Variable<String>(
        $MessageEntriesTable.$convertercategory.toSql(category),
      );
    }
    if (!nullToAbsent || groupName != null) {
      map['group_name'] = Variable<String>(groupName);
    }
    return map;
  }

  MessageEntriesCompanion toCompanion(bool nullToAbsent) {
    return MessageEntriesCompanion(
      id: Value(id),
      conversationPeer: Value(conversationPeer),
      fromCallsign: fromCallsign == null && nullToAbsent
          ? const Value.absent()
          : Value(fromCallsign),
      addressee: addressee == null && nullToAbsent
          ? const Value.absent()
          : Value(addressee),
      body: Value(body),
      timestamp: Value(timestamp),
      isOutgoing: Value(isOutgoing),
      wireId: wireId == null && nullToAbsent
          ? const Value.absent()
          : Value(wireId),
      status: Value(status),
      retryCount: Value(retryCount),
      category: Value(category),
      groupName: groupName == null && nullToAbsent
          ? const Value.absent()
          : Value(groupName),
    );
  }

  factory MessageEntryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MessageEntryRow(
      id: serializer.fromJson<String>(json['id']),
      conversationPeer: serializer.fromJson<String>(json['conversationPeer']),
      fromCallsign: serializer.fromJson<String?>(json['fromCallsign']),
      addressee: serializer.fromJson<String?>(json['addressee']),
      body: serializer.fromJson<String>(json['body']),
      timestamp: serializer.fromJson<int>(json['timestamp']),
      isOutgoing: serializer.fromJson<bool>(json['isOutgoing']),
      wireId: serializer.fromJson<String?>(json['wireId']),
      status: $MessageEntriesTable.$converterstatus.fromJson(
        serializer.fromJson<String>(json['status']),
      ),
      retryCount: serializer.fromJson<int>(json['retryCount']),
      category: $MessageEntriesTable.$convertercategory.fromJson(
        serializer.fromJson<String>(json['category']),
      ),
      groupName: serializer.fromJson<String?>(json['groupName']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'conversationPeer': serializer.toJson<String>(conversationPeer),
      'fromCallsign': serializer.toJson<String?>(fromCallsign),
      'addressee': serializer.toJson<String?>(addressee),
      'body': serializer.toJson<String>(body),
      'timestamp': serializer.toJson<int>(timestamp),
      'isOutgoing': serializer.toJson<bool>(isOutgoing),
      'wireId': serializer.toJson<String?>(wireId),
      'status': serializer.toJson<String>(
        $MessageEntriesTable.$converterstatus.toJson(status),
      ),
      'retryCount': serializer.toJson<int>(retryCount),
      'category': serializer.toJson<String>(
        $MessageEntriesTable.$convertercategory.toJson(category),
      ),
      'groupName': serializer.toJson<String?>(groupName),
    };
  }

  MessageEntryRow copyWith({
    String? id,
    String? conversationPeer,
    Value<String?> fromCallsign = const Value.absent(),
    Value<String?> addressee = const Value.absent(),
    String? body,
    int? timestamp,
    bool? isOutgoing,
    Value<String?> wireId = const Value.absent(),
    MessageStatus? status,
    int? retryCount,
    MessageCategory? category,
    Value<String?> groupName = const Value.absent(),
  }) => MessageEntryRow(
    id: id ?? this.id,
    conversationPeer: conversationPeer ?? this.conversationPeer,
    fromCallsign: fromCallsign.present ? fromCallsign.value : this.fromCallsign,
    addressee: addressee.present ? addressee.value : this.addressee,
    body: body ?? this.body,
    timestamp: timestamp ?? this.timestamp,
    isOutgoing: isOutgoing ?? this.isOutgoing,
    wireId: wireId.present ? wireId.value : this.wireId,
    status: status ?? this.status,
    retryCount: retryCount ?? this.retryCount,
    category: category ?? this.category,
    groupName: groupName.present ? groupName.value : this.groupName,
  );
  MessageEntryRow copyWithCompanion(MessageEntriesCompanion data) {
    return MessageEntryRow(
      id: data.id.present ? data.id.value : this.id,
      conversationPeer: data.conversationPeer.present
          ? data.conversationPeer.value
          : this.conversationPeer,
      fromCallsign: data.fromCallsign.present
          ? data.fromCallsign.value
          : this.fromCallsign,
      addressee: data.addressee.present ? data.addressee.value : this.addressee,
      body: data.body.present ? data.body.value : this.body,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      isOutgoing: data.isOutgoing.present
          ? data.isOutgoing.value
          : this.isOutgoing,
      wireId: data.wireId.present ? data.wireId.value : this.wireId,
      status: data.status.present ? data.status.value : this.status,
      retryCount: data.retryCount.present
          ? data.retryCount.value
          : this.retryCount,
      category: data.category.present ? data.category.value : this.category,
      groupName: data.groupName.present ? data.groupName.value : this.groupName,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MessageEntryRow(')
          ..write('id: $id, ')
          ..write('conversationPeer: $conversationPeer, ')
          ..write('fromCallsign: $fromCallsign, ')
          ..write('addressee: $addressee, ')
          ..write('body: $body, ')
          ..write('timestamp: $timestamp, ')
          ..write('isOutgoing: $isOutgoing, ')
          ..write('wireId: $wireId, ')
          ..write('status: $status, ')
          ..write('retryCount: $retryCount, ')
          ..write('category: $category, ')
          ..write('groupName: $groupName')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    conversationPeer,
    fromCallsign,
    addressee,
    body,
    timestamp,
    isOutgoing,
    wireId,
    status,
    retryCount,
    category,
    groupName,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MessageEntryRow &&
          other.id == this.id &&
          other.conversationPeer == this.conversationPeer &&
          other.fromCallsign == this.fromCallsign &&
          other.addressee == this.addressee &&
          other.body == this.body &&
          other.timestamp == this.timestamp &&
          other.isOutgoing == this.isOutgoing &&
          other.wireId == this.wireId &&
          other.status == this.status &&
          other.retryCount == this.retryCount &&
          other.category == this.category &&
          other.groupName == this.groupName);
}

class MessageEntriesCompanion extends UpdateCompanion<MessageEntryRow> {
  final Value<String> id;
  final Value<String> conversationPeer;
  final Value<String?> fromCallsign;
  final Value<String?> addressee;
  final Value<String> body;
  final Value<int> timestamp;
  final Value<bool> isOutgoing;
  final Value<String?> wireId;
  final Value<MessageStatus> status;
  final Value<int> retryCount;
  final Value<MessageCategory> category;
  final Value<String?> groupName;
  final Value<int> rowid;
  const MessageEntriesCompanion({
    this.id = const Value.absent(),
    this.conversationPeer = const Value.absent(),
    this.fromCallsign = const Value.absent(),
    this.addressee = const Value.absent(),
    this.body = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.isOutgoing = const Value.absent(),
    this.wireId = const Value.absent(),
    this.status = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.category = const Value.absent(),
    this.groupName = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessageEntriesCompanion.insert({
    required String id,
    required String conversationPeer,
    this.fromCallsign = const Value.absent(),
    this.addressee = const Value.absent(),
    required String body,
    required int timestamp,
    required bool isOutgoing,
    this.wireId = const Value.absent(),
    required MessageStatus status,
    this.retryCount = const Value.absent(),
    required MessageCategory category,
    this.groupName = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       conversationPeer = Value(conversationPeer),
       body = Value(body),
       timestamp = Value(timestamp),
       isOutgoing = Value(isOutgoing),
       status = Value(status),
       category = Value(category);
  static Insertable<MessageEntryRow> custom({
    Expression<String>? id,
    Expression<String>? conversationPeer,
    Expression<String>? fromCallsign,
    Expression<String>? addressee,
    Expression<String>? body,
    Expression<int>? timestamp,
    Expression<bool>? isOutgoing,
    Expression<String>? wireId,
    Expression<String>? status,
    Expression<int>? retryCount,
    Expression<String>? category,
    Expression<String>? groupName,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (conversationPeer != null) 'conversation_peer': conversationPeer,
      if (fromCallsign != null) 'from_callsign': fromCallsign,
      if (addressee != null) 'addressee': addressee,
      if (body != null) 'body': body,
      if (timestamp != null) 'timestamp': timestamp,
      if (isOutgoing != null) 'is_outgoing': isOutgoing,
      if (wireId != null) 'wire_id': wireId,
      if (status != null) 'status': status,
      if (retryCount != null) 'retry_count': retryCount,
      if (category != null) 'category': category,
      if (groupName != null) 'group_name': groupName,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessageEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? conversationPeer,
    Value<String?>? fromCallsign,
    Value<String?>? addressee,
    Value<String>? body,
    Value<int>? timestamp,
    Value<bool>? isOutgoing,
    Value<String?>? wireId,
    Value<MessageStatus>? status,
    Value<int>? retryCount,
    Value<MessageCategory>? category,
    Value<String?>? groupName,
    Value<int>? rowid,
  }) {
    return MessageEntriesCompanion(
      id: id ?? this.id,
      conversationPeer: conversationPeer ?? this.conversationPeer,
      fromCallsign: fromCallsign ?? this.fromCallsign,
      addressee: addressee ?? this.addressee,
      body: body ?? this.body,
      timestamp: timestamp ?? this.timestamp,
      isOutgoing: isOutgoing ?? this.isOutgoing,
      wireId: wireId ?? this.wireId,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      category: category ?? this.category,
      groupName: groupName ?? this.groupName,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (conversationPeer.present) {
      map['conversation_peer'] = Variable<String>(conversationPeer.value);
    }
    if (fromCallsign.present) {
      map['from_callsign'] = Variable<String>(fromCallsign.value);
    }
    if (addressee.present) {
      map['addressee'] = Variable<String>(addressee.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<int>(timestamp.value);
    }
    if (isOutgoing.present) {
      map['is_outgoing'] = Variable<bool>(isOutgoing.value);
    }
    if (wireId.present) {
      map['wire_id'] = Variable<String>(wireId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $MessageEntriesTable.$converterstatus.toSql(status.value),
      );
    }
    if (retryCount.present) {
      map['retry_count'] = Variable<int>(retryCount.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(
        $MessageEntriesTable.$convertercategory.toSql(category.value),
      );
    }
    if (groupName.present) {
      map['group_name'] = Variable<String>(groupName.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessageEntriesCompanion(')
          ..write('id: $id, ')
          ..write('conversationPeer: $conversationPeer, ')
          ..write('fromCallsign: $fromCallsign, ')
          ..write('addressee: $addressee, ')
          ..write('body: $body, ')
          ..write('timestamp: $timestamp, ')
          ..write('isOutgoing: $isOutgoing, ')
          ..write('wireId: $wireId, ')
          ..write('status: $status, ')
          ..write('retryCount: $retryCount, ')
          ..write('category: $category, ')
          ..write('groupName: $groupName, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GroupMessageEntriesTable extends GroupMessageEntries
    with TableInfo<$GroupMessageEntriesTable, GroupMessageEntryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GroupMessageEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _groupNameMeta = const VerificationMeta(
    'groupName',
  );
  @override
  late final GeneratedColumn<String> groupName = GeneratedColumn<String>(
    'group_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fromCallsignMeta = const VerificationMeta(
    'fromCallsign',
  );
  @override
  late final GeneratedColumn<String> fromCallsign = GeneratedColumn<String>(
    'from_callsign',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<int> timestamp = GeneratedColumn<int>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    groupName,
    fromCallsign,
    body,
    timestamp,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'group_message_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<GroupMessageEntryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('group_name')) {
      context.handle(
        _groupNameMeta,
        groupName.isAcceptableOrUnknown(data['group_name']!, _groupNameMeta),
      );
    } else if (isInserting) {
      context.missing(_groupNameMeta);
    }
    if (data.containsKey('from_callsign')) {
      context.handle(
        _fromCallsignMeta,
        fromCallsign.isAcceptableOrUnknown(
          data['from_callsign']!,
          _fromCallsignMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fromCallsignMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GroupMessageEntryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GroupMessageEntryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      groupName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_name'],
      )!,
      fromCallsign: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}from_callsign'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}timestamp'],
      )!,
    );
  }

  @override
  $GroupMessageEntriesTable createAlias(String alias) {
    return $GroupMessageEntriesTable(attachedDatabase, alias);
  }
}

class GroupMessageEntryRow extends DataClass
    implements Insertable<GroupMessageEntryRow> {
  final String id;
  final String groupName;
  final String fromCallsign;
  final String body;
  final int timestamp;
  const GroupMessageEntryRow({
    required this.id,
    required this.groupName,
    required this.fromCallsign,
    required this.body,
    required this.timestamp,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['group_name'] = Variable<String>(groupName);
    map['from_callsign'] = Variable<String>(fromCallsign);
    map['body'] = Variable<String>(body);
    map['timestamp'] = Variable<int>(timestamp);
    return map;
  }

  GroupMessageEntriesCompanion toCompanion(bool nullToAbsent) {
    return GroupMessageEntriesCompanion(
      id: Value(id),
      groupName: Value(groupName),
      fromCallsign: Value(fromCallsign),
      body: Value(body),
      timestamp: Value(timestamp),
    );
  }

  factory GroupMessageEntryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GroupMessageEntryRow(
      id: serializer.fromJson<String>(json['id']),
      groupName: serializer.fromJson<String>(json['groupName']),
      fromCallsign: serializer.fromJson<String>(json['fromCallsign']),
      body: serializer.fromJson<String>(json['body']),
      timestamp: serializer.fromJson<int>(json['timestamp']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'groupName': serializer.toJson<String>(groupName),
      'fromCallsign': serializer.toJson<String>(fromCallsign),
      'body': serializer.toJson<String>(body),
      'timestamp': serializer.toJson<int>(timestamp),
    };
  }

  GroupMessageEntryRow copyWith({
    String? id,
    String? groupName,
    String? fromCallsign,
    String? body,
    int? timestamp,
  }) => GroupMessageEntryRow(
    id: id ?? this.id,
    groupName: groupName ?? this.groupName,
    fromCallsign: fromCallsign ?? this.fromCallsign,
    body: body ?? this.body,
    timestamp: timestamp ?? this.timestamp,
  );
  GroupMessageEntryRow copyWithCompanion(GroupMessageEntriesCompanion data) {
    return GroupMessageEntryRow(
      id: data.id.present ? data.id.value : this.id,
      groupName: data.groupName.present ? data.groupName.value : this.groupName,
      fromCallsign: data.fromCallsign.present
          ? data.fromCallsign.value
          : this.fromCallsign,
      body: data.body.present ? data.body.value : this.body,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GroupMessageEntryRow(')
          ..write('id: $id, ')
          ..write('groupName: $groupName, ')
          ..write('fromCallsign: $fromCallsign, ')
          ..write('body: $body, ')
          ..write('timestamp: $timestamp')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, groupName, fromCallsign, body, timestamp);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GroupMessageEntryRow &&
          other.id == this.id &&
          other.groupName == this.groupName &&
          other.fromCallsign == this.fromCallsign &&
          other.body == this.body &&
          other.timestamp == this.timestamp);
}

class GroupMessageEntriesCompanion
    extends UpdateCompanion<GroupMessageEntryRow> {
  final Value<String> id;
  final Value<String> groupName;
  final Value<String> fromCallsign;
  final Value<String> body;
  final Value<int> timestamp;
  final Value<int> rowid;
  const GroupMessageEntriesCompanion({
    this.id = const Value.absent(),
    this.groupName = const Value.absent(),
    this.fromCallsign = const Value.absent(),
    this.body = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GroupMessageEntriesCompanion.insert({
    required String id,
    required String groupName,
    required String fromCallsign,
    required String body,
    required int timestamp,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       groupName = Value(groupName),
       fromCallsign = Value(fromCallsign),
       body = Value(body),
       timestamp = Value(timestamp);
  static Insertable<GroupMessageEntryRow> custom({
    Expression<String>? id,
    Expression<String>? groupName,
    Expression<String>? fromCallsign,
    Expression<String>? body,
    Expression<int>? timestamp,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (groupName != null) 'group_name': groupName,
      if (fromCallsign != null) 'from_callsign': fromCallsign,
      if (body != null) 'body': body,
      if (timestamp != null) 'timestamp': timestamp,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GroupMessageEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? groupName,
    Value<String>? fromCallsign,
    Value<String>? body,
    Value<int>? timestamp,
    Value<int>? rowid,
  }) {
    return GroupMessageEntriesCompanion(
      id: id ?? this.id,
      groupName: groupName ?? this.groupName,
      fromCallsign: fromCallsign ?? this.fromCallsign,
      body: body ?? this.body,
      timestamp: timestamp ?? this.timestamp,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (groupName.present) {
      map['group_name'] = Variable<String>(groupName.value);
    }
    if (fromCallsign.present) {
      map['from_callsign'] = Variable<String>(fromCallsign.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<int>(timestamp.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GroupMessageEntriesCompanion(')
          ..write('id: $id, ')
          ..write('groupName: $groupName, ')
          ..write('fromCallsign: $fromCallsign, ')
          ..write('body: $body, ')
          ..write('timestamp: $timestamp, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BulletinsTable extends Bulletins
    with TableInfo<$BulletinsTable, BulletinRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BulletinsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sourceCallsignMeta = const VerificationMeta(
    'sourceCallsign',
  );
  @override
  late final GeneratedColumn<String> sourceCallsign = GeneratedColumn<String>(
    'source_callsign',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _addresseeMeta = const VerificationMeta(
    'addressee',
  );
  @override
  late final GeneratedColumn<String> addressee = GeneratedColumn<String>(
    'addressee',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _firstHeardAtMeta = const VerificationMeta(
    'firstHeardAt',
  );
  @override
  late final GeneratedColumn<int> firstHeardAt = GeneratedColumn<int>(
    'first_heard_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastHeardAtMeta = const VerificationMeta(
    'lastHeardAt',
  );
  @override
  late final GeneratedColumn<int> lastHeardAt = GeneratedColumn<int>(
    'last_heard_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _heardCountMeta = const VerificationMeta(
    'heardCount',
  );
  @override
  late final GeneratedColumn<int> heardCount = GeneratedColumn<int>(
    'heard_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  @override
  late final GeneratedColumnWithTypeConverter<BulletinCategory, String>
  category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<BulletinCategory>($BulletinsTable.$convertercategory);
  static const VerificationMeta _lineNumberMeta = const VerificationMeta(
    'lineNumber',
  );
  @override
  late final GeneratedColumn<String> lineNumber = GeneratedColumn<String>(
    'line_number',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _groupNameMeta = const VerificationMeta(
    'groupName',
  );
  @override
  late final GeneratedColumn<String> groupName = GeneratedColumn<String>(
    'group_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Set<BulletinTransport>, String>
  transports = GeneratedColumn<String>(
    'transports',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  ).withConverter<Set<BulletinTransport>>($BulletinsTable.$convertertransports);
  static const VerificationMeta _receivedLatMeta = const VerificationMeta(
    'receivedLat',
  );
  @override
  late final GeneratedColumn<double> receivedLat = GeneratedColumn<double>(
    'received_lat',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _receivedLonMeta = const VerificationMeta(
    'receivedLon',
  );
  @override
  late final GeneratedColumn<double> receivedLon = GeneratedColumn<double>(
    'received_lon',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isReadMeta = const VerificationMeta('isRead');
  @override
  late final GeneratedColumn<bool> isRead = GeneratedColumn<bool>(
    'is_read',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_read" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    sourceCallsign,
    addressee,
    body,
    firstHeardAt,
    lastHeardAt,
    heardCount,
    category,
    lineNumber,
    groupName,
    transports,
    receivedLat,
    receivedLon,
    isRead,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'bulletins';
  @override
  VerificationContext validateIntegrity(
    Insertable<BulletinRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('source_callsign')) {
      context.handle(
        _sourceCallsignMeta,
        sourceCallsign.isAcceptableOrUnknown(
          data['source_callsign']!,
          _sourceCallsignMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sourceCallsignMeta);
    }
    if (data.containsKey('addressee')) {
      context.handle(
        _addresseeMeta,
        addressee.isAcceptableOrUnknown(data['addressee']!, _addresseeMeta),
      );
    } else if (isInserting) {
      context.missing(_addresseeMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('first_heard_at')) {
      context.handle(
        _firstHeardAtMeta,
        firstHeardAt.isAcceptableOrUnknown(
          data['first_heard_at']!,
          _firstHeardAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_firstHeardAtMeta);
    }
    if (data.containsKey('last_heard_at')) {
      context.handle(
        _lastHeardAtMeta,
        lastHeardAt.isAcceptableOrUnknown(
          data['last_heard_at']!,
          _lastHeardAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastHeardAtMeta);
    }
    if (data.containsKey('heard_count')) {
      context.handle(
        _heardCountMeta,
        heardCount.isAcceptableOrUnknown(data['heard_count']!, _heardCountMeta),
      );
    }
    if (data.containsKey('line_number')) {
      context.handle(
        _lineNumberMeta,
        lineNumber.isAcceptableOrUnknown(data['line_number']!, _lineNumberMeta),
      );
    } else if (isInserting) {
      context.missing(_lineNumberMeta);
    }
    if (data.containsKey('group_name')) {
      context.handle(
        _groupNameMeta,
        groupName.isAcceptableOrUnknown(data['group_name']!, _groupNameMeta),
      );
    }
    if (data.containsKey('received_lat')) {
      context.handle(
        _receivedLatMeta,
        receivedLat.isAcceptableOrUnknown(
          data['received_lat']!,
          _receivedLatMeta,
        ),
      );
    }
    if (data.containsKey('received_lon')) {
      context.handle(
        _receivedLonMeta,
        receivedLon.isAcceptableOrUnknown(
          data['received_lon']!,
          _receivedLonMeta,
        ),
      );
    }
    if (data.containsKey('is_read')) {
      context.handle(
        _isReadMeta,
        isRead.isAcceptableOrUnknown(data['is_read']!, _isReadMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sourceCallsign, addressee};
  @override
  BulletinRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BulletinRow(
      sourceCallsign: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_callsign'],
      )!,
      addressee: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}addressee'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      firstHeardAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}first_heard_at'],
      )!,
      lastHeardAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_heard_at'],
      )!,
      heardCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}heard_count'],
      )!,
      category: $BulletinsTable.$convertercategory.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}category'],
        )!,
      ),
      lineNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}line_number'],
      )!,
      groupName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_name'],
      ),
      transports: $BulletinsTable.$convertertransports.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}transports'],
        )!,
      ),
      receivedLat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}received_lat'],
      ),
      receivedLon: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}received_lon'],
      ),
      isRead: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_read'],
      )!,
    );
  }

  @override
  $BulletinsTable createAlias(String alias) {
    return $BulletinsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<BulletinCategory, String, String>
  $convertercategory = const EnumNameConverter(BulletinCategory.values);
  static TypeConverter<Set<BulletinTransport>, String> $convertertransports =
      const BulletinTransportsConverter();
}

class BulletinRow extends DataClass implements Insertable<BulletinRow> {
  final String sourceCallsign;
  final String addressee;
  final String body;
  final int firstHeardAt;
  final int lastHeardAt;
  final int heardCount;
  final BulletinCategory category;
  final String lineNumber;
  final String? groupName;
  final Set<BulletinTransport> transports;
  final double? receivedLat;
  final double? receivedLon;
  final bool isRead;
  const BulletinRow({
    required this.sourceCallsign,
    required this.addressee,
    required this.body,
    required this.firstHeardAt,
    required this.lastHeardAt,
    required this.heardCount,
    required this.category,
    required this.lineNumber,
    this.groupName,
    required this.transports,
    this.receivedLat,
    this.receivedLon,
    required this.isRead,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_callsign'] = Variable<String>(sourceCallsign);
    map['addressee'] = Variable<String>(addressee);
    map['body'] = Variable<String>(body);
    map['first_heard_at'] = Variable<int>(firstHeardAt);
    map['last_heard_at'] = Variable<int>(lastHeardAt);
    map['heard_count'] = Variable<int>(heardCount);
    {
      map['category'] = Variable<String>(
        $BulletinsTable.$convertercategory.toSql(category),
      );
    }
    map['line_number'] = Variable<String>(lineNumber);
    if (!nullToAbsent || groupName != null) {
      map['group_name'] = Variable<String>(groupName);
    }
    {
      map['transports'] = Variable<String>(
        $BulletinsTable.$convertertransports.toSql(transports),
      );
    }
    if (!nullToAbsent || receivedLat != null) {
      map['received_lat'] = Variable<double>(receivedLat);
    }
    if (!nullToAbsent || receivedLon != null) {
      map['received_lon'] = Variable<double>(receivedLon);
    }
    map['is_read'] = Variable<bool>(isRead);
    return map;
  }

  BulletinsCompanion toCompanion(bool nullToAbsent) {
    return BulletinsCompanion(
      sourceCallsign: Value(sourceCallsign),
      addressee: Value(addressee),
      body: Value(body),
      firstHeardAt: Value(firstHeardAt),
      lastHeardAt: Value(lastHeardAt),
      heardCount: Value(heardCount),
      category: Value(category),
      lineNumber: Value(lineNumber),
      groupName: groupName == null && nullToAbsent
          ? const Value.absent()
          : Value(groupName),
      transports: Value(transports),
      receivedLat: receivedLat == null && nullToAbsent
          ? const Value.absent()
          : Value(receivedLat),
      receivedLon: receivedLon == null && nullToAbsent
          ? const Value.absent()
          : Value(receivedLon),
      isRead: Value(isRead),
    );
  }

  factory BulletinRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BulletinRow(
      sourceCallsign: serializer.fromJson<String>(json['sourceCallsign']),
      addressee: serializer.fromJson<String>(json['addressee']),
      body: serializer.fromJson<String>(json['body']),
      firstHeardAt: serializer.fromJson<int>(json['firstHeardAt']),
      lastHeardAt: serializer.fromJson<int>(json['lastHeardAt']),
      heardCount: serializer.fromJson<int>(json['heardCount']),
      category: $BulletinsTable.$convertercategory.fromJson(
        serializer.fromJson<String>(json['category']),
      ),
      lineNumber: serializer.fromJson<String>(json['lineNumber']),
      groupName: serializer.fromJson<String?>(json['groupName']),
      transports: serializer.fromJson<Set<BulletinTransport>>(
        json['transports'],
      ),
      receivedLat: serializer.fromJson<double?>(json['receivedLat']),
      receivedLon: serializer.fromJson<double?>(json['receivedLon']),
      isRead: serializer.fromJson<bool>(json['isRead']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sourceCallsign': serializer.toJson<String>(sourceCallsign),
      'addressee': serializer.toJson<String>(addressee),
      'body': serializer.toJson<String>(body),
      'firstHeardAt': serializer.toJson<int>(firstHeardAt),
      'lastHeardAt': serializer.toJson<int>(lastHeardAt),
      'heardCount': serializer.toJson<int>(heardCount),
      'category': serializer.toJson<String>(
        $BulletinsTable.$convertercategory.toJson(category),
      ),
      'lineNumber': serializer.toJson<String>(lineNumber),
      'groupName': serializer.toJson<String?>(groupName),
      'transports': serializer.toJson<Set<BulletinTransport>>(transports),
      'receivedLat': serializer.toJson<double?>(receivedLat),
      'receivedLon': serializer.toJson<double?>(receivedLon),
      'isRead': serializer.toJson<bool>(isRead),
    };
  }

  BulletinRow copyWith({
    String? sourceCallsign,
    String? addressee,
    String? body,
    int? firstHeardAt,
    int? lastHeardAt,
    int? heardCount,
    BulletinCategory? category,
    String? lineNumber,
    Value<String?> groupName = const Value.absent(),
    Set<BulletinTransport>? transports,
    Value<double?> receivedLat = const Value.absent(),
    Value<double?> receivedLon = const Value.absent(),
    bool? isRead,
  }) => BulletinRow(
    sourceCallsign: sourceCallsign ?? this.sourceCallsign,
    addressee: addressee ?? this.addressee,
    body: body ?? this.body,
    firstHeardAt: firstHeardAt ?? this.firstHeardAt,
    lastHeardAt: lastHeardAt ?? this.lastHeardAt,
    heardCount: heardCount ?? this.heardCount,
    category: category ?? this.category,
    lineNumber: lineNumber ?? this.lineNumber,
    groupName: groupName.present ? groupName.value : this.groupName,
    transports: transports ?? this.transports,
    receivedLat: receivedLat.present ? receivedLat.value : this.receivedLat,
    receivedLon: receivedLon.present ? receivedLon.value : this.receivedLon,
    isRead: isRead ?? this.isRead,
  );
  BulletinRow copyWithCompanion(BulletinsCompanion data) {
    return BulletinRow(
      sourceCallsign: data.sourceCallsign.present
          ? data.sourceCallsign.value
          : this.sourceCallsign,
      addressee: data.addressee.present ? data.addressee.value : this.addressee,
      body: data.body.present ? data.body.value : this.body,
      firstHeardAt: data.firstHeardAt.present
          ? data.firstHeardAt.value
          : this.firstHeardAt,
      lastHeardAt: data.lastHeardAt.present
          ? data.lastHeardAt.value
          : this.lastHeardAt,
      heardCount: data.heardCount.present
          ? data.heardCount.value
          : this.heardCount,
      category: data.category.present ? data.category.value : this.category,
      lineNumber: data.lineNumber.present
          ? data.lineNumber.value
          : this.lineNumber,
      groupName: data.groupName.present ? data.groupName.value : this.groupName,
      transports: data.transports.present
          ? data.transports.value
          : this.transports,
      receivedLat: data.receivedLat.present
          ? data.receivedLat.value
          : this.receivedLat,
      receivedLon: data.receivedLon.present
          ? data.receivedLon.value
          : this.receivedLon,
      isRead: data.isRead.present ? data.isRead.value : this.isRead,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BulletinRow(')
          ..write('sourceCallsign: $sourceCallsign, ')
          ..write('addressee: $addressee, ')
          ..write('body: $body, ')
          ..write('firstHeardAt: $firstHeardAt, ')
          ..write('lastHeardAt: $lastHeardAt, ')
          ..write('heardCount: $heardCount, ')
          ..write('category: $category, ')
          ..write('lineNumber: $lineNumber, ')
          ..write('groupName: $groupName, ')
          ..write('transports: $transports, ')
          ..write('receivedLat: $receivedLat, ')
          ..write('receivedLon: $receivedLon, ')
          ..write('isRead: $isRead')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sourceCallsign,
    addressee,
    body,
    firstHeardAt,
    lastHeardAt,
    heardCount,
    category,
    lineNumber,
    groupName,
    transports,
    receivedLat,
    receivedLon,
    isRead,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BulletinRow &&
          other.sourceCallsign == this.sourceCallsign &&
          other.addressee == this.addressee &&
          other.body == this.body &&
          other.firstHeardAt == this.firstHeardAt &&
          other.lastHeardAt == this.lastHeardAt &&
          other.heardCount == this.heardCount &&
          other.category == this.category &&
          other.lineNumber == this.lineNumber &&
          other.groupName == this.groupName &&
          other.transports == this.transports &&
          other.receivedLat == this.receivedLat &&
          other.receivedLon == this.receivedLon &&
          other.isRead == this.isRead);
}

class BulletinsCompanion extends UpdateCompanion<BulletinRow> {
  final Value<String> sourceCallsign;
  final Value<String> addressee;
  final Value<String> body;
  final Value<int> firstHeardAt;
  final Value<int> lastHeardAt;
  final Value<int> heardCount;
  final Value<BulletinCategory> category;
  final Value<String> lineNumber;
  final Value<String?> groupName;
  final Value<Set<BulletinTransport>> transports;
  final Value<double?> receivedLat;
  final Value<double?> receivedLon;
  final Value<bool> isRead;
  final Value<int> rowid;
  const BulletinsCompanion({
    this.sourceCallsign = const Value.absent(),
    this.addressee = const Value.absent(),
    this.body = const Value.absent(),
    this.firstHeardAt = const Value.absent(),
    this.lastHeardAt = const Value.absent(),
    this.heardCount = const Value.absent(),
    this.category = const Value.absent(),
    this.lineNumber = const Value.absent(),
    this.groupName = const Value.absent(),
    this.transports = const Value.absent(),
    this.receivedLat = const Value.absent(),
    this.receivedLon = const Value.absent(),
    this.isRead = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BulletinsCompanion.insert({
    required String sourceCallsign,
    required String addressee,
    required String body,
    required int firstHeardAt,
    required int lastHeardAt,
    this.heardCount = const Value.absent(),
    required BulletinCategory category,
    required String lineNumber,
    this.groupName = const Value.absent(),
    this.transports = const Value.absent(),
    this.receivedLat = const Value.absent(),
    this.receivedLon = const Value.absent(),
    this.isRead = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : sourceCallsign = Value(sourceCallsign),
       addressee = Value(addressee),
       body = Value(body),
       firstHeardAt = Value(firstHeardAt),
       lastHeardAt = Value(lastHeardAt),
       category = Value(category),
       lineNumber = Value(lineNumber);
  static Insertable<BulletinRow> custom({
    Expression<String>? sourceCallsign,
    Expression<String>? addressee,
    Expression<String>? body,
    Expression<int>? firstHeardAt,
    Expression<int>? lastHeardAt,
    Expression<int>? heardCount,
    Expression<String>? category,
    Expression<String>? lineNumber,
    Expression<String>? groupName,
    Expression<String>? transports,
    Expression<double>? receivedLat,
    Expression<double>? receivedLon,
    Expression<bool>? isRead,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sourceCallsign != null) 'source_callsign': sourceCallsign,
      if (addressee != null) 'addressee': addressee,
      if (body != null) 'body': body,
      if (firstHeardAt != null) 'first_heard_at': firstHeardAt,
      if (lastHeardAt != null) 'last_heard_at': lastHeardAt,
      if (heardCount != null) 'heard_count': heardCount,
      if (category != null) 'category': category,
      if (lineNumber != null) 'line_number': lineNumber,
      if (groupName != null) 'group_name': groupName,
      if (transports != null) 'transports': transports,
      if (receivedLat != null) 'received_lat': receivedLat,
      if (receivedLon != null) 'received_lon': receivedLon,
      if (isRead != null) 'is_read': isRead,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BulletinsCompanion copyWith({
    Value<String>? sourceCallsign,
    Value<String>? addressee,
    Value<String>? body,
    Value<int>? firstHeardAt,
    Value<int>? lastHeardAt,
    Value<int>? heardCount,
    Value<BulletinCategory>? category,
    Value<String>? lineNumber,
    Value<String?>? groupName,
    Value<Set<BulletinTransport>>? transports,
    Value<double?>? receivedLat,
    Value<double?>? receivedLon,
    Value<bool>? isRead,
    Value<int>? rowid,
  }) {
    return BulletinsCompanion(
      sourceCallsign: sourceCallsign ?? this.sourceCallsign,
      addressee: addressee ?? this.addressee,
      body: body ?? this.body,
      firstHeardAt: firstHeardAt ?? this.firstHeardAt,
      lastHeardAt: lastHeardAt ?? this.lastHeardAt,
      heardCount: heardCount ?? this.heardCount,
      category: category ?? this.category,
      lineNumber: lineNumber ?? this.lineNumber,
      groupName: groupName ?? this.groupName,
      transports: transports ?? this.transports,
      receivedLat: receivedLat ?? this.receivedLat,
      receivedLon: receivedLon ?? this.receivedLon,
      isRead: isRead ?? this.isRead,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sourceCallsign.present) {
      map['source_callsign'] = Variable<String>(sourceCallsign.value);
    }
    if (addressee.present) {
      map['addressee'] = Variable<String>(addressee.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (firstHeardAt.present) {
      map['first_heard_at'] = Variable<int>(firstHeardAt.value);
    }
    if (lastHeardAt.present) {
      map['last_heard_at'] = Variable<int>(lastHeardAt.value);
    }
    if (heardCount.present) {
      map['heard_count'] = Variable<int>(heardCount.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(
        $BulletinsTable.$convertercategory.toSql(category.value),
      );
    }
    if (lineNumber.present) {
      map['line_number'] = Variable<String>(lineNumber.value);
    }
    if (groupName.present) {
      map['group_name'] = Variable<String>(groupName.value);
    }
    if (transports.present) {
      map['transports'] = Variable<String>(
        $BulletinsTable.$convertertransports.toSql(transports.value),
      );
    }
    if (receivedLat.present) {
      map['received_lat'] = Variable<double>(receivedLat.value);
    }
    if (receivedLon.present) {
      map['received_lon'] = Variable<double>(receivedLon.value);
    }
    if (isRead.present) {
      map['is_read'] = Variable<bool>(isRead.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BulletinsCompanion(')
          ..write('sourceCallsign: $sourceCallsign, ')
          ..write('addressee: $addressee, ')
          ..write('body: $body, ')
          ..write('firstHeardAt: $firstHeardAt, ')
          ..write('lastHeardAt: $lastHeardAt, ')
          ..write('heardCount: $heardCount, ')
          ..write('category: $category, ')
          ..write('lineNumber: $lineNumber, ')
          ..write('groupName: $groupName, ')
          ..write('transports: $transports, ')
          ..write('receivedLat: $receivedLat, ')
          ..write('receivedLon: $receivedLon, ')
          ..write('isRead: $isRead, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutgoingBulletinsTable extends OutgoingBulletins
    with TableInfo<$OutgoingBulletinsTable, OutgoingBulletinRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutgoingBulletinsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _addresseeMeta = const VerificationMeta(
    'addressee',
  );
  @override
  late final GeneratedColumn<String> addressee = GeneratedColumn<String>(
    'addressee',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _intervalSecondsMeta = const VerificationMeta(
    'intervalSeconds',
  );
  @override
  late final GeneratedColumn<int> intervalSeconds = GeneratedColumn<int>(
    'interval_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _transmissionCountMeta = const VerificationMeta(
    'transmissionCount',
  );
  @override
  late final GeneratedColumn<int> transmissionCount = GeneratedColumn<int>(
    'transmission_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  @override
  late final GeneratedColumn<int> expiresAt = GeneratedColumn<int>(
    'expires_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastTransmittedAtMeta = const VerificationMeta(
    'lastTransmittedAt',
  );
  @override
  late final GeneratedColumn<int> lastTransmittedAt = GeneratedColumn<int>(
    'last_transmitted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _viaRfMeta = const VerificationMeta('viaRf');
  @override
  late final GeneratedColumn<bool> viaRf = GeneratedColumn<bool>(
    'via_rf',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("via_rf" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _viaAprsIsMeta = const VerificationMeta(
    'viaAprsIs',
  );
  @override
  late final GeneratedColumn<bool> viaAprsIs = GeneratedColumn<bool>(
    'via_aprs_is',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("via_aprs_is" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    addressee,
    body,
    intervalSeconds,
    transmissionCount,
    expiresAt,
    createdAt,
    lastTransmittedAt,
    viaRf,
    viaAprsIs,
    enabled,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outgoing_bulletins';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutgoingBulletinRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('addressee')) {
      context.handle(
        _addresseeMeta,
        addressee.isAcceptableOrUnknown(data['addressee']!, _addresseeMeta),
      );
    } else if (isInserting) {
      context.missing(_addresseeMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('interval_seconds')) {
      context.handle(
        _intervalSecondsMeta,
        intervalSeconds.isAcceptableOrUnknown(
          data['interval_seconds']!,
          _intervalSecondsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_intervalSecondsMeta);
    }
    if (data.containsKey('transmission_count')) {
      context.handle(
        _transmissionCountMeta,
        transmissionCount.isAcceptableOrUnknown(
          data['transmission_count']!,
          _transmissionCountMeta,
        ),
      );
    }
    if (data.containsKey('expires_at')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('last_transmitted_at')) {
      context.handle(
        _lastTransmittedAtMeta,
        lastTransmittedAt.isAcceptableOrUnknown(
          data['last_transmitted_at']!,
          _lastTransmittedAtMeta,
        ),
      );
    }
    if (data.containsKey('via_rf')) {
      context.handle(
        _viaRfMeta,
        viaRf.isAcceptableOrUnknown(data['via_rf']!, _viaRfMeta),
      );
    }
    if (data.containsKey('via_aprs_is')) {
      context.handle(
        _viaAprsIsMeta,
        viaAprsIs.isAcceptableOrUnknown(data['via_aprs_is']!, _viaAprsIsMeta),
      );
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OutgoingBulletinRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutgoingBulletinRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      addressee: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}addressee'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      intervalSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}interval_seconds'],
      )!,
      transmissionCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}transmission_count'],
      )!,
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expires_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      lastTransmittedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_transmitted_at'],
      ),
      viaRf: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}via_rf'],
      )!,
      viaAprsIs: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}via_aprs_is'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
    );
  }

  @override
  $OutgoingBulletinsTable createAlias(String alias) {
    return $OutgoingBulletinsTable(attachedDatabase, alias);
  }
}

class OutgoingBulletinRow extends DataClass
    implements Insertable<OutgoingBulletinRow> {
  final int id;
  final String addressee;
  final String body;
  final int intervalSeconds;
  final int transmissionCount;
  final int? expiresAt;
  final int createdAt;
  final int? lastTransmittedAt;
  final bool viaRf;
  final bool viaAprsIs;
  final bool enabled;
  const OutgoingBulletinRow({
    required this.id,
    required this.addressee,
    required this.body,
    required this.intervalSeconds,
    required this.transmissionCount,
    this.expiresAt,
    required this.createdAt,
    this.lastTransmittedAt,
    required this.viaRf,
    required this.viaAprsIs,
    required this.enabled,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['addressee'] = Variable<String>(addressee);
    map['body'] = Variable<String>(body);
    map['interval_seconds'] = Variable<int>(intervalSeconds);
    map['transmission_count'] = Variable<int>(transmissionCount);
    if (!nullToAbsent || expiresAt != null) {
      map['expires_at'] = Variable<int>(expiresAt);
    }
    map['created_at'] = Variable<int>(createdAt);
    if (!nullToAbsent || lastTransmittedAt != null) {
      map['last_transmitted_at'] = Variable<int>(lastTransmittedAt);
    }
    map['via_rf'] = Variable<bool>(viaRf);
    map['via_aprs_is'] = Variable<bool>(viaAprsIs);
    map['enabled'] = Variable<bool>(enabled);
    return map;
  }

  OutgoingBulletinsCompanion toCompanion(bool nullToAbsent) {
    return OutgoingBulletinsCompanion(
      id: Value(id),
      addressee: Value(addressee),
      body: Value(body),
      intervalSeconds: Value(intervalSeconds),
      transmissionCount: Value(transmissionCount),
      expiresAt: expiresAt == null && nullToAbsent
          ? const Value.absent()
          : Value(expiresAt),
      createdAt: Value(createdAt),
      lastTransmittedAt: lastTransmittedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastTransmittedAt),
      viaRf: Value(viaRf),
      viaAprsIs: Value(viaAprsIs),
      enabled: Value(enabled),
    );
  }

  factory OutgoingBulletinRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutgoingBulletinRow(
      id: serializer.fromJson<int>(json['id']),
      addressee: serializer.fromJson<String>(json['addressee']),
      body: serializer.fromJson<String>(json['body']),
      intervalSeconds: serializer.fromJson<int>(json['intervalSeconds']),
      transmissionCount: serializer.fromJson<int>(json['transmissionCount']),
      expiresAt: serializer.fromJson<int?>(json['expiresAt']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      lastTransmittedAt: serializer.fromJson<int?>(json['lastTransmittedAt']),
      viaRf: serializer.fromJson<bool>(json['viaRf']),
      viaAprsIs: serializer.fromJson<bool>(json['viaAprsIs']),
      enabled: serializer.fromJson<bool>(json['enabled']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'addressee': serializer.toJson<String>(addressee),
      'body': serializer.toJson<String>(body),
      'intervalSeconds': serializer.toJson<int>(intervalSeconds),
      'transmissionCount': serializer.toJson<int>(transmissionCount),
      'expiresAt': serializer.toJson<int?>(expiresAt),
      'createdAt': serializer.toJson<int>(createdAt),
      'lastTransmittedAt': serializer.toJson<int?>(lastTransmittedAt),
      'viaRf': serializer.toJson<bool>(viaRf),
      'viaAprsIs': serializer.toJson<bool>(viaAprsIs),
      'enabled': serializer.toJson<bool>(enabled),
    };
  }

  OutgoingBulletinRow copyWith({
    int? id,
    String? addressee,
    String? body,
    int? intervalSeconds,
    int? transmissionCount,
    Value<int?> expiresAt = const Value.absent(),
    int? createdAt,
    Value<int?> lastTransmittedAt = const Value.absent(),
    bool? viaRf,
    bool? viaAprsIs,
    bool? enabled,
  }) => OutgoingBulletinRow(
    id: id ?? this.id,
    addressee: addressee ?? this.addressee,
    body: body ?? this.body,
    intervalSeconds: intervalSeconds ?? this.intervalSeconds,
    transmissionCount: transmissionCount ?? this.transmissionCount,
    expiresAt: expiresAt.present ? expiresAt.value : this.expiresAt,
    createdAt: createdAt ?? this.createdAt,
    lastTransmittedAt: lastTransmittedAt.present
        ? lastTransmittedAt.value
        : this.lastTransmittedAt,
    viaRf: viaRf ?? this.viaRf,
    viaAprsIs: viaAprsIs ?? this.viaAprsIs,
    enabled: enabled ?? this.enabled,
  );
  OutgoingBulletinRow copyWithCompanion(OutgoingBulletinsCompanion data) {
    return OutgoingBulletinRow(
      id: data.id.present ? data.id.value : this.id,
      addressee: data.addressee.present ? data.addressee.value : this.addressee,
      body: data.body.present ? data.body.value : this.body,
      intervalSeconds: data.intervalSeconds.present
          ? data.intervalSeconds.value
          : this.intervalSeconds,
      transmissionCount: data.transmissionCount.present
          ? data.transmissionCount.value
          : this.transmissionCount,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastTransmittedAt: data.lastTransmittedAt.present
          ? data.lastTransmittedAt.value
          : this.lastTransmittedAt,
      viaRf: data.viaRf.present ? data.viaRf.value : this.viaRf,
      viaAprsIs: data.viaAprsIs.present ? data.viaAprsIs.value : this.viaAprsIs,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutgoingBulletinRow(')
          ..write('id: $id, ')
          ..write('addressee: $addressee, ')
          ..write('body: $body, ')
          ..write('intervalSeconds: $intervalSeconds, ')
          ..write('transmissionCount: $transmissionCount, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastTransmittedAt: $lastTransmittedAt, ')
          ..write('viaRf: $viaRf, ')
          ..write('viaAprsIs: $viaAprsIs, ')
          ..write('enabled: $enabled')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    addressee,
    body,
    intervalSeconds,
    transmissionCount,
    expiresAt,
    createdAt,
    lastTransmittedAt,
    viaRf,
    viaAprsIs,
    enabled,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutgoingBulletinRow &&
          other.id == this.id &&
          other.addressee == this.addressee &&
          other.body == this.body &&
          other.intervalSeconds == this.intervalSeconds &&
          other.transmissionCount == this.transmissionCount &&
          other.expiresAt == this.expiresAt &&
          other.createdAt == this.createdAt &&
          other.lastTransmittedAt == this.lastTransmittedAt &&
          other.viaRf == this.viaRf &&
          other.viaAprsIs == this.viaAprsIs &&
          other.enabled == this.enabled);
}

class OutgoingBulletinsCompanion extends UpdateCompanion<OutgoingBulletinRow> {
  final Value<int> id;
  final Value<String> addressee;
  final Value<String> body;
  final Value<int> intervalSeconds;
  final Value<int> transmissionCount;
  final Value<int?> expiresAt;
  final Value<int> createdAt;
  final Value<int?> lastTransmittedAt;
  final Value<bool> viaRf;
  final Value<bool> viaAprsIs;
  final Value<bool> enabled;
  const OutgoingBulletinsCompanion({
    this.id = const Value.absent(),
    this.addressee = const Value.absent(),
    this.body = const Value.absent(),
    this.intervalSeconds = const Value.absent(),
    this.transmissionCount = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastTransmittedAt = const Value.absent(),
    this.viaRf = const Value.absent(),
    this.viaAprsIs = const Value.absent(),
    this.enabled = const Value.absent(),
  });
  OutgoingBulletinsCompanion.insert({
    this.id = const Value.absent(),
    required String addressee,
    required String body,
    required int intervalSeconds,
    this.transmissionCount = const Value.absent(),
    this.expiresAt = const Value.absent(),
    required int createdAt,
    this.lastTransmittedAt = const Value.absent(),
    this.viaRf = const Value.absent(),
    this.viaAprsIs = const Value.absent(),
    this.enabled = const Value.absent(),
  }) : addressee = Value(addressee),
       body = Value(body),
       intervalSeconds = Value(intervalSeconds),
       createdAt = Value(createdAt);
  static Insertable<OutgoingBulletinRow> custom({
    Expression<int>? id,
    Expression<String>? addressee,
    Expression<String>? body,
    Expression<int>? intervalSeconds,
    Expression<int>? transmissionCount,
    Expression<int>? expiresAt,
    Expression<int>? createdAt,
    Expression<int>? lastTransmittedAt,
    Expression<bool>? viaRf,
    Expression<bool>? viaAprsIs,
    Expression<bool>? enabled,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (addressee != null) 'addressee': addressee,
      if (body != null) 'body': body,
      if (intervalSeconds != null) 'interval_seconds': intervalSeconds,
      if (transmissionCount != null) 'transmission_count': transmissionCount,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (createdAt != null) 'created_at': createdAt,
      if (lastTransmittedAt != null) 'last_transmitted_at': lastTransmittedAt,
      if (viaRf != null) 'via_rf': viaRf,
      if (viaAprsIs != null) 'via_aprs_is': viaAprsIs,
      if (enabled != null) 'enabled': enabled,
    });
  }

  OutgoingBulletinsCompanion copyWith({
    Value<int>? id,
    Value<String>? addressee,
    Value<String>? body,
    Value<int>? intervalSeconds,
    Value<int>? transmissionCount,
    Value<int?>? expiresAt,
    Value<int>? createdAt,
    Value<int?>? lastTransmittedAt,
    Value<bool>? viaRf,
    Value<bool>? viaAprsIs,
    Value<bool>? enabled,
  }) {
    return OutgoingBulletinsCompanion(
      id: id ?? this.id,
      addressee: addressee ?? this.addressee,
      body: body ?? this.body,
      intervalSeconds: intervalSeconds ?? this.intervalSeconds,
      transmissionCount: transmissionCount ?? this.transmissionCount,
      expiresAt: expiresAt ?? this.expiresAt,
      createdAt: createdAt ?? this.createdAt,
      lastTransmittedAt: lastTransmittedAt ?? this.lastTransmittedAt,
      viaRf: viaRf ?? this.viaRf,
      viaAprsIs: viaAprsIs ?? this.viaAprsIs,
      enabled: enabled ?? this.enabled,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (addressee.present) {
      map['addressee'] = Variable<String>(addressee.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (intervalSeconds.present) {
      map['interval_seconds'] = Variable<int>(intervalSeconds.value);
    }
    if (transmissionCount.present) {
      map['transmission_count'] = Variable<int>(transmissionCount.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<int>(expiresAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (lastTransmittedAt.present) {
      map['last_transmitted_at'] = Variable<int>(lastTransmittedAt.value);
    }
    if (viaRf.present) {
      map['via_rf'] = Variable<bool>(viaRf.value);
    }
    if (viaAprsIs.present) {
      map['via_aprs_is'] = Variable<bool>(viaAprsIs.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutgoingBulletinsCompanion(')
          ..write('id: $id, ')
          ..write('addressee: $addressee, ')
          ..write('body: $body, ')
          ..write('intervalSeconds: $intervalSeconds, ')
          ..write('transmissionCount: $transmissionCount, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastTransmittedAt: $lastTransmittedAt, ')
          ..write('viaRf: $viaRf, ')
          ..write('viaAprsIs: $viaAprsIs, ')
          ..write('enabled: $enabled')
          ..write(')'))
        .toString();
  }
}

abstract class _$MeridianDatabase extends GeneratedDatabase {
  _$MeridianDatabase(QueryExecutor e) : super(e);
  $MeridianDatabaseManager get managers => $MeridianDatabaseManager(this);
  late final $StationsTable stations = $StationsTable(this);
  late final $PositionHistoryTable positionHistory = $PositionHistoryTable(
    this,
  );
  late final $PacketsTable packets = $PacketsTable(this);
  late final $ConversationsTable conversations = $ConversationsTable(this);
  late final $MessageEntriesTable messageEntries = $MessageEntriesTable(this);
  late final $GroupMessageEntriesTable groupMessageEntries =
      $GroupMessageEntriesTable(this);
  late final $BulletinsTable bulletins = $BulletinsTable(this);
  late final $OutgoingBulletinsTable outgoingBulletins =
      $OutgoingBulletinsTable(this);
  late final StationDao stationDao = StationDao(this as MeridianDatabase);
  late final PacketDao packetDao = PacketDao(this as MeridianDatabase);
  late final MessageDao messageDao = MessageDao(this as MeridianDatabase);
  late final BulletinDao bulletinDao = BulletinDao(this as MeridianDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    stations,
    positionHistory,
    packets,
    conversations,
    messageEntries,
    groupMessageEntries,
    bulletins,
    outgoingBulletins,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'stations',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('position_history', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'conversations',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('message_entries', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$StationsTableCreateCompanionBuilder =
    StationsCompanion Function({
      required String callsign,
      required String symbolTable,
      required String symbolCode,
      required String comment,
      required String rawPacket,
      Value<String?> device,
      required int lastHeard,
      required StationType stationType,
      required MessageCapability messageCapability,
      Value<String?> capabilities,
      required double lat,
      required double lon,
      Value<int> rowid,
    });
typedef $$StationsTableUpdateCompanionBuilder =
    StationsCompanion Function({
      Value<String> callsign,
      Value<String> symbolTable,
      Value<String> symbolCode,
      Value<String> comment,
      Value<String> rawPacket,
      Value<String?> device,
      Value<int> lastHeard,
      Value<StationType> stationType,
      Value<MessageCapability> messageCapability,
      Value<String?> capabilities,
      Value<double> lat,
      Value<double> lon,
      Value<int> rowid,
    });

final class $$StationsTableReferences
    extends BaseReferences<_$MeridianDatabase, $StationsTable, StationRow> {
  $$StationsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$PositionHistoryTable, List<PositionHistoryRow>>
  _positionHistoryRefsTable(_$MeridianDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.positionHistory,
        aliasName: $_aliasNameGenerator(
          db.stations.callsign,
          db.positionHistory.callsign,
        ),
      );

  $$PositionHistoryTableProcessedTableManager get positionHistoryRefs {
    final manager =
        $$PositionHistoryTableTableManager($_db, $_db.positionHistory).filter(
          (f) =>
              f.callsign.callsign.sqlEquals($_itemColumn<String>('callsign')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _positionHistoryRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$StationsTableFilterComposer
    extends Composer<_$MeridianDatabase, $StationsTable> {
  $$StationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get callsign => $composableBuilder(
    column: $table.callsign,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get symbolTable => $composableBuilder(
    column: $table.symbolTable,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get symbolCode => $composableBuilder(
    column: $table.symbolCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get comment => $composableBuilder(
    column: $table.comment,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rawPacket => $composableBuilder(
    column: $table.rawPacket,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get device => $composableBuilder(
    column: $table.device,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastHeard => $composableBuilder(
    column: $table.lastHeard,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<StationType, StationType, String>
  get stationType => $composableBuilder(
    column: $table.stationType,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<MessageCapability, MessageCapability, String>
  get messageCapability => $composableBuilder(
    column: $table.messageCapability,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get capabilities => $composableBuilder(
    column: $table.capabilities,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lon => $composableBuilder(
    column: $table.lon,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> positionHistoryRefs(
    Expression<bool> Function($$PositionHistoryTableFilterComposer f) f,
  ) {
    final $$PositionHistoryTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.callsign,
      referencedTable: $db.positionHistory,
      getReferencedColumn: (t) => t.callsign,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PositionHistoryTableFilterComposer(
            $db: $db,
            $table: $db.positionHistory,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$StationsTableOrderingComposer
    extends Composer<_$MeridianDatabase, $StationsTable> {
  $$StationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get callsign => $composableBuilder(
    column: $table.callsign,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get symbolTable => $composableBuilder(
    column: $table.symbolTable,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get symbolCode => $composableBuilder(
    column: $table.symbolCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get comment => $composableBuilder(
    column: $table.comment,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rawPacket => $composableBuilder(
    column: $table.rawPacket,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get device => $composableBuilder(
    column: $table.device,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastHeard => $composableBuilder(
    column: $table.lastHeard,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stationType => $composableBuilder(
    column: $table.stationType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messageCapability => $composableBuilder(
    column: $table.messageCapability,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get capabilities => $composableBuilder(
    column: $table.capabilities,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lon => $composableBuilder(
    column: $table.lon,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StationsTableAnnotationComposer
    extends Composer<_$MeridianDatabase, $StationsTable> {
  $$StationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get callsign =>
      $composableBuilder(column: $table.callsign, builder: (column) => column);

  GeneratedColumn<String> get symbolTable => $composableBuilder(
    column: $table.symbolTable,
    builder: (column) => column,
  );

  GeneratedColumn<String> get symbolCode => $composableBuilder(
    column: $table.symbolCode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get comment =>
      $composableBuilder(column: $table.comment, builder: (column) => column);

  GeneratedColumn<String> get rawPacket =>
      $composableBuilder(column: $table.rawPacket, builder: (column) => column);

  GeneratedColumn<String> get device =>
      $composableBuilder(column: $table.device, builder: (column) => column);

  GeneratedColumn<int> get lastHeard =>
      $composableBuilder(column: $table.lastHeard, builder: (column) => column);

  GeneratedColumnWithTypeConverter<StationType, String> get stationType =>
      $composableBuilder(
        column: $table.stationType,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<MessageCapability, String>
  get messageCapability => $composableBuilder(
    column: $table.messageCapability,
    builder: (column) => column,
  );

  GeneratedColumn<String> get capabilities => $composableBuilder(
    column: $table.capabilities,
    builder: (column) => column,
  );

  GeneratedColumn<double> get lat =>
      $composableBuilder(column: $table.lat, builder: (column) => column);

  GeneratedColumn<double> get lon =>
      $composableBuilder(column: $table.lon, builder: (column) => column);

  Expression<T> positionHistoryRefs<T extends Object>(
    Expression<T> Function($$PositionHistoryTableAnnotationComposer a) f,
  ) {
    final $$PositionHistoryTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.callsign,
      referencedTable: $db.positionHistory,
      getReferencedColumn: (t) => t.callsign,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PositionHistoryTableAnnotationComposer(
            $db: $db,
            $table: $db.positionHistory,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$StationsTableTableManager
    extends
        RootTableManager<
          _$MeridianDatabase,
          $StationsTable,
          StationRow,
          $$StationsTableFilterComposer,
          $$StationsTableOrderingComposer,
          $$StationsTableAnnotationComposer,
          $$StationsTableCreateCompanionBuilder,
          $$StationsTableUpdateCompanionBuilder,
          (StationRow, $$StationsTableReferences),
          StationRow,
          PrefetchHooks Function({bool positionHistoryRefs})
        > {
  $$StationsTableTableManager(_$MeridianDatabase db, $StationsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> callsign = const Value.absent(),
                Value<String> symbolTable = const Value.absent(),
                Value<String> symbolCode = const Value.absent(),
                Value<String> comment = const Value.absent(),
                Value<String> rawPacket = const Value.absent(),
                Value<String?> device = const Value.absent(),
                Value<int> lastHeard = const Value.absent(),
                Value<StationType> stationType = const Value.absent(),
                Value<MessageCapability> messageCapability =
                    const Value.absent(),
                Value<String?> capabilities = const Value.absent(),
                Value<double> lat = const Value.absent(),
                Value<double> lon = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StationsCompanion(
                callsign: callsign,
                symbolTable: symbolTable,
                symbolCode: symbolCode,
                comment: comment,
                rawPacket: rawPacket,
                device: device,
                lastHeard: lastHeard,
                stationType: stationType,
                messageCapability: messageCapability,
                capabilities: capabilities,
                lat: lat,
                lon: lon,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String callsign,
                required String symbolTable,
                required String symbolCode,
                required String comment,
                required String rawPacket,
                Value<String?> device = const Value.absent(),
                required int lastHeard,
                required StationType stationType,
                required MessageCapability messageCapability,
                Value<String?> capabilities = const Value.absent(),
                required double lat,
                required double lon,
                Value<int> rowid = const Value.absent(),
              }) => StationsCompanion.insert(
                callsign: callsign,
                symbolTable: symbolTable,
                symbolCode: symbolCode,
                comment: comment,
                rawPacket: rawPacket,
                device: device,
                lastHeard: lastHeard,
                stationType: stationType,
                messageCapability: messageCapability,
                capabilities: capabilities,
                lat: lat,
                lon: lon,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$StationsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({positionHistoryRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (positionHistoryRefs) db.positionHistory,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (positionHistoryRefs)
                    await $_getPrefetchedData<
                      StationRow,
                      $StationsTable,
                      PositionHistoryRow
                    >(
                      currentTable: table,
                      referencedTable: $$StationsTableReferences
                          ._positionHistoryRefsTable(db),
                      managerFromTypedResult: (p0) => $$StationsTableReferences(
                        db,
                        table,
                        p0,
                      ).positionHistoryRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.callsign == item.callsign,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$StationsTableProcessedTableManager =
    ProcessedTableManager<
      _$MeridianDatabase,
      $StationsTable,
      StationRow,
      $$StationsTableFilterComposer,
      $$StationsTableOrderingComposer,
      $$StationsTableAnnotationComposer,
      $$StationsTableCreateCompanionBuilder,
      $$StationsTableUpdateCompanionBuilder,
      (StationRow, $$StationsTableReferences),
      StationRow,
      PrefetchHooks Function({bool positionHistoryRefs})
    >;
typedef $$PositionHistoryTableCreateCompanionBuilder =
    PositionHistoryCompanion Function({
      Value<int> id,
      required String callsign,
      required double latitude,
      required double longitude,
      required int timestamp,
    });
typedef $$PositionHistoryTableUpdateCompanionBuilder =
    PositionHistoryCompanion Function({
      Value<int> id,
      Value<String> callsign,
      Value<double> latitude,
      Value<double> longitude,
      Value<int> timestamp,
    });

final class $$PositionHistoryTableReferences
    extends
        BaseReferences<
          _$MeridianDatabase,
          $PositionHistoryTable,
          PositionHistoryRow
        > {
  $$PositionHistoryTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $StationsTable _callsignTable(_$MeridianDatabase db) =>
      db.stations.createAlias(
        $_aliasNameGenerator(db.positionHistory.callsign, db.stations.callsign),
      );

  $$StationsTableProcessedTableManager get callsign {
    final $_column = $_itemColumn<String>('callsign')!;

    final manager = $$StationsTableTableManager(
      $_db,
      $_db.stations,
    ).filter((f) => f.callsign.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_callsignTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PositionHistoryTableFilterComposer
    extends Composer<_$MeridianDatabase, $PositionHistoryTable> {
  $$PositionHistoryTableFilterComposer({
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

  ColumnFilters<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  $$StationsTableFilterComposer get callsign {
    final $$StationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.callsign,
      referencedTable: $db.stations,
      getReferencedColumn: (t) => t.callsign,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StationsTableFilterComposer(
            $db: $db,
            $table: $db.stations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PositionHistoryTableOrderingComposer
    extends Composer<_$MeridianDatabase, $PositionHistoryTable> {
  $$PositionHistoryTableOrderingComposer({
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

  ColumnOrderings<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  $$StationsTableOrderingComposer get callsign {
    final $$StationsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.callsign,
      referencedTable: $db.stations,
      getReferencedColumn: (t) => t.callsign,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StationsTableOrderingComposer(
            $db: $db,
            $table: $db.stations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PositionHistoryTableAnnotationComposer
    extends Composer<_$MeridianDatabase, $PositionHistoryTable> {
  $$PositionHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<int> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  $$StationsTableAnnotationComposer get callsign {
    final $$StationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.callsign,
      referencedTable: $db.stations,
      getReferencedColumn: (t) => t.callsign,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StationsTableAnnotationComposer(
            $db: $db,
            $table: $db.stations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PositionHistoryTableTableManager
    extends
        RootTableManager<
          _$MeridianDatabase,
          $PositionHistoryTable,
          PositionHistoryRow,
          $$PositionHistoryTableFilterComposer,
          $$PositionHistoryTableOrderingComposer,
          $$PositionHistoryTableAnnotationComposer,
          $$PositionHistoryTableCreateCompanionBuilder,
          $$PositionHistoryTableUpdateCompanionBuilder,
          (PositionHistoryRow, $$PositionHistoryTableReferences),
          PositionHistoryRow,
          PrefetchHooks Function({bool callsign})
        > {
  $$PositionHistoryTableTableManager(
    _$MeridianDatabase db,
    $PositionHistoryTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PositionHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PositionHistoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PositionHistoryTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> callsign = const Value.absent(),
                Value<double> latitude = const Value.absent(),
                Value<double> longitude = const Value.absent(),
                Value<int> timestamp = const Value.absent(),
              }) => PositionHistoryCompanion(
                id: id,
                callsign: callsign,
                latitude: latitude,
                longitude: longitude,
                timestamp: timestamp,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String callsign,
                required double latitude,
                required double longitude,
                required int timestamp,
              }) => PositionHistoryCompanion.insert(
                id: id,
                callsign: callsign,
                latitude: latitude,
                longitude: longitude,
                timestamp: timestamp,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$PositionHistoryTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({callsign = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (callsign) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.callsign,
                                referencedTable:
                                    $$PositionHistoryTableReferences
                                        ._callsignTable(db),
                                referencedColumn:
                                    $$PositionHistoryTableReferences
                                        ._callsignTable(db)
                                        .callsign,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$PositionHistoryTableProcessedTableManager =
    ProcessedTableManager<
      _$MeridianDatabase,
      $PositionHistoryTable,
      PositionHistoryRow,
      $$PositionHistoryTableFilterComposer,
      $$PositionHistoryTableOrderingComposer,
      $$PositionHistoryTableAnnotationComposer,
      $$PositionHistoryTableCreateCompanionBuilder,
      $$PositionHistoryTableUpdateCompanionBuilder,
      (PositionHistoryRow, $$PositionHistoryTableReferences),
      PositionHistoryRow,
      PrefetchHooks Function({bool callsign})
    >;
typedef $$PacketsTableCreateCompanionBuilder =
    PacketsCompanion Function({
      Value<int> id,
      required String rawLine,
      required PacketTypeTag packetType,
      required String sourceCallsign,
      Value<String?> destination,
      required int receivedAt,
      Value<bool> isOutgoing,
      required PacketSource sourceChannel,
    });
typedef $$PacketsTableUpdateCompanionBuilder =
    PacketsCompanion Function({
      Value<int> id,
      Value<String> rawLine,
      Value<PacketTypeTag> packetType,
      Value<String> sourceCallsign,
      Value<String?> destination,
      Value<int> receivedAt,
      Value<bool> isOutgoing,
      Value<PacketSource> sourceChannel,
    });

class $$PacketsTableFilterComposer
    extends Composer<_$MeridianDatabase, $PacketsTable> {
  $$PacketsTableFilterComposer({
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

  ColumnFilters<String> get rawLine => $composableBuilder(
    column: $table.rawLine,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<PacketTypeTag, PacketTypeTag, String>
  get packetType => $composableBuilder(
    column: $table.packetType,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get sourceCallsign => $composableBuilder(
    column: $table.sourceCallsign,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get destination => $composableBuilder(
    column: $table.destination,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get receivedAt => $composableBuilder(
    column: $table.receivedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isOutgoing => $composableBuilder(
    column: $table.isOutgoing,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<PacketSource, PacketSource, String>
  get sourceChannel => $composableBuilder(
    column: $table.sourceChannel,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );
}

class $$PacketsTableOrderingComposer
    extends Composer<_$MeridianDatabase, $PacketsTable> {
  $$PacketsTableOrderingComposer({
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

  ColumnOrderings<String> get rawLine => $composableBuilder(
    column: $table.rawLine,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get packetType => $composableBuilder(
    column: $table.packetType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceCallsign => $composableBuilder(
    column: $table.sourceCallsign,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get destination => $composableBuilder(
    column: $table.destination,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get receivedAt => $composableBuilder(
    column: $table.receivedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isOutgoing => $composableBuilder(
    column: $table.isOutgoing,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceChannel => $composableBuilder(
    column: $table.sourceChannel,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PacketsTableAnnotationComposer
    extends Composer<_$MeridianDatabase, $PacketsTable> {
  $$PacketsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get rawLine =>
      $composableBuilder(column: $table.rawLine, builder: (column) => column);

  GeneratedColumnWithTypeConverter<PacketTypeTag, String> get packetType =>
      $composableBuilder(
        column: $table.packetType,
        builder: (column) => column,
      );

  GeneratedColumn<String> get sourceCallsign => $composableBuilder(
    column: $table.sourceCallsign,
    builder: (column) => column,
  );

  GeneratedColumn<String> get destination => $composableBuilder(
    column: $table.destination,
    builder: (column) => column,
  );

  GeneratedColumn<int> get receivedAt => $composableBuilder(
    column: $table.receivedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isOutgoing => $composableBuilder(
    column: $table.isOutgoing,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<PacketSource, String> get sourceChannel =>
      $composableBuilder(
        column: $table.sourceChannel,
        builder: (column) => column,
      );
}

class $$PacketsTableTableManager
    extends
        RootTableManager<
          _$MeridianDatabase,
          $PacketsTable,
          PacketRow,
          $$PacketsTableFilterComposer,
          $$PacketsTableOrderingComposer,
          $$PacketsTableAnnotationComposer,
          $$PacketsTableCreateCompanionBuilder,
          $$PacketsTableUpdateCompanionBuilder,
          (
            PacketRow,
            BaseReferences<_$MeridianDatabase, $PacketsTable, PacketRow>,
          ),
          PacketRow,
          PrefetchHooks Function()
        > {
  $$PacketsTableTableManager(_$MeridianDatabase db, $PacketsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PacketsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PacketsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PacketsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> rawLine = const Value.absent(),
                Value<PacketTypeTag> packetType = const Value.absent(),
                Value<String> sourceCallsign = const Value.absent(),
                Value<String?> destination = const Value.absent(),
                Value<int> receivedAt = const Value.absent(),
                Value<bool> isOutgoing = const Value.absent(),
                Value<PacketSource> sourceChannel = const Value.absent(),
              }) => PacketsCompanion(
                id: id,
                rawLine: rawLine,
                packetType: packetType,
                sourceCallsign: sourceCallsign,
                destination: destination,
                receivedAt: receivedAt,
                isOutgoing: isOutgoing,
                sourceChannel: sourceChannel,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String rawLine,
                required PacketTypeTag packetType,
                required String sourceCallsign,
                Value<String?> destination = const Value.absent(),
                required int receivedAt,
                Value<bool> isOutgoing = const Value.absent(),
                required PacketSource sourceChannel,
              }) => PacketsCompanion.insert(
                id: id,
                rawLine: rawLine,
                packetType: packetType,
                sourceCallsign: sourceCallsign,
                destination: destination,
                receivedAt: receivedAt,
                isOutgoing: isOutgoing,
                sourceChannel: sourceChannel,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PacketsTableProcessedTableManager =
    ProcessedTableManager<
      _$MeridianDatabase,
      $PacketsTable,
      PacketRow,
      $$PacketsTableFilterComposer,
      $$PacketsTableOrderingComposer,
      $$PacketsTableAnnotationComposer,
      $$PacketsTableCreateCompanionBuilder,
      $$PacketsTableUpdateCompanionBuilder,
      (PacketRow, BaseReferences<_$MeridianDatabase, $PacketsTable, PacketRow>),
      PacketRow,
      PrefetchHooks Function()
    >;
typedef $$ConversationsTableCreateCompanionBuilder =
    ConversationsCompanion Function({
      required String peerCallsign,
      required int lastMessageAt,
      Value<int> unreadCount,
      Value<int> rowid,
    });
typedef $$ConversationsTableUpdateCompanionBuilder =
    ConversationsCompanion Function({
      Value<String> peerCallsign,
      Value<int> lastMessageAt,
      Value<int> unreadCount,
      Value<int> rowid,
    });

final class $$ConversationsTableReferences
    extends
        BaseReferences<
          _$MeridianDatabase,
          $ConversationsTable,
          ConversationRow
        > {
  $$ConversationsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$MessageEntriesTable, List<MessageEntryRow>>
  _messageEntriesRefsTable(_$MeridianDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.messageEntries,
        aliasName: $_aliasNameGenerator(
          db.conversations.peerCallsign,
          db.messageEntries.conversationPeer,
        ),
      );

  $$MessageEntriesTableProcessedTableManager get messageEntriesRefs {
    final manager = $$MessageEntriesTableTableManager($_db, $_db.messageEntries)
        .filter(
          (f) => f.conversationPeer.peerCallsign.sqlEquals(
            $_itemColumn<String>('peer_callsign')!,
          ),
        );

    final cache = $_typedResult.readTableOrNull(_messageEntriesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ConversationsTableFilterComposer
    extends Composer<_$MeridianDatabase, $ConversationsTable> {
  $$ConversationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get peerCallsign => $composableBuilder(
    column: $table.peerCallsign,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastMessageAt => $composableBuilder(
    column: $table.lastMessageAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> messageEntriesRefs(
    Expression<bool> Function($$MessageEntriesTableFilterComposer f) f,
  ) {
    final $$MessageEntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.peerCallsign,
      referencedTable: $db.messageEntries,
      getReferencedColumn: (t) => t.conversationPeer,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessageEntriesTableFilterComposer(
            $db: $db,
            $table: $db.messageEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ConversationsTableOrderingComposer
    extends Composer<_$MeridianDatabase, $ConversationsTable> {
  $$ConversationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get peerCallsign => $composableBuilder(
    column: $table.peerCallsign,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastMessageAt => $composableBuilder(
    column: $table.lastMessageAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ConversationsTableAnnotationComposer
    extends Composer<_$MeridianDatabase, $ConversationsTable> {
  $$ConversationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get peerCallsign => $composableBuilder(
    column: $table.peerCallsign,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastMessageAt => $composableBuilder(
    column: $table.lastMessageAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => column,
  );

  Expression<T> messageEntriesRefs<T extends Object>(
    Expression<T> Function($$MessageEntriesTableAnnotationComposer a) f,
  ) {
    final $$MessageEntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.peerCallsign,
      referencedTable: $db.messageEntries,
      getReferencedColumn: (t) => t.conversationPeer,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessageEntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.messageEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ConversationsTableTableManager
    extends
        RootTableManager<
          _$MeridianDatabase,
          $ConversationsTable,
          ConversationRow,
          $$ConversationsTableFilterComposer,
          $$ConversationsTableOrderingComposer,
          $$ConversationsTableAnnotationComposer,
          $$ConversationsTableCreateCompanionBuilder,
          $$ConversationsTableUpdateCompanionBuilder,
          (ConversationRow, $$ConversationsTableReferences),
          ConversationRow,
          PrefetchHooks Function({bool messageEntriesRefs})
        > {
  $$ConversationsTableTableManager(
    _$MeridianDatabase db,
    $ConversationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConversationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ConversationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ConversationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> peerCallsign = const Value.absent(),
                Value<int> lastMessageAt = const Value.absent(),
                Value<int> unreadCount = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConversationsCompanion(
                peerCallsign: peerCallsign,
                lastMessageAt: lastMessageAt,
                unreadCount: unreadCount,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String peerCallsign,
                required int lastMessageAt,
                Value<int> unreadCount = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConversationsCompanion.insert(
                peerCallsign: peerCallsign,
                lastMessageAt: lastMessageAt,
                unreadCount: unreadCount,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ConversationsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({messageEntriesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (messageEntriesRefs) db.messageEntries,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (messageEntriesRefs)
                    await $_getPrefetchedData<
                      ConversationRow,
                      $ConversationsTable,
                      MessageEntryRow
                    >(
                      currentTable: table,
                      referencedTable: $$ConversationsTableReferences
                          ._messageEntriesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$ConversationsTableReferences(
                            db,
                            table,
                            p0,
                          ).messageEntriesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.conversationPeer == item.peerCallsign,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ConversationsTableProcessedTableManager =
    ProcessedTableManager<
      _$MeridianDatabase,
      $ConversationsTable,
      ConversationRow,
      $$ConversationsTableFilterComposer,
      $$ConversationsTableOrderingComposer,
      $$ConversationsTableAnnotationComposer,
      $$ConversationsTableCreateCompanionBuilder,
      $$ConversationsTableUpdateCompanionBuilder,
      (ConversationRow, $$ConversationsTableReferences),
      ConversationRow,
      PrefetchHooks Function({bool messageEntriesRefs})
    >;
typedef $$MessageEntriesTableCreateCompanionBuilder =
    MessageEntriesCompanion Function({
      required String id,
      required String conversationPeer,
      Value<String?> fromCallsign,
      Value<String?> addressee,
      required String body,
      required int timestamp,
      required bool isOutgoing,
      Value<String?> wireId,
      required MessageStatus status,
      Value<int> retryCount,
      required MessageCategory category,
      Value<String?> groupName,
      Value<int> rowid,
    });
typedef $$MessageEntriesTableUpdateCompanionBuilder =
    MessageEntriesCompanion Function({
      Value<String> id,
      Value<String> conversationPeer,
      Value<String?> fromCallsign,
      Value<String?> addressee,
      Value<String> body,
      Value<int> timestamp,
      Value<bool> isOutgoing,
      Value<String?> wireId,
      Value<MessageStatus> status,
      Value<int> retryCount,
      Value<MessageCategory> category,
      Value<String?> groupName,
      Value<int> rowid,
    });

final class $$MessageEntriesTableReferences
    extends
        BaseReferences<
          _$MeridianDatabase,
          $MessageEntriesTable,
          MessageEntryRow
        > {
  $$MessageEntriesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ConversationsTable _conversationPeerTable(_$MeridianDatabase db) =>
      db.conversations.createAlias(
        $_aliasNameGenerator(
          db.messageEntries.conversationPeer,
          db.conversations.peerCallsign,
        ),
      );

  $$ConversationsTableProcessedTableManager get conversationPeer {
    final $_column = $_itemColumn<String>('conversation_peer')!;

    final manager = $$ConversationsTableTableManager(
      $_db,
      $_db.conversations,
    ).filter((f) => f.peerCallsign.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_conversationPeerTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$MessageEntriesTableFilterComposer
    extends Composer<_$MeridianDatabase, $MessageEntriesTable> {
  $$MessageEntriesTableFilterComposer({
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

  ColumnFilters<String> get fromCallsign => $composableBuilder(
    column: $table.fromCallsign,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get addressee => $composableBuilder(
    column: $table.addressee,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isOutgoing => $composableBuilder(
    column: $table.isOutgoing,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get wireId => $composableBuilder(
    column: $table.wireId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<MessageStatus, MessageStatus, String>
  get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<MessageCategory, MessageCategory, String>
  get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get groupName => $composableBuilder(
    column: $table.groupName,
    builder: (column) => ColumnFilters(column),
  );

  $$ConversationsTableFilterComposer get conversationPeer {
    final $$ConversationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationPeer,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.peerCallsign,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableFilterComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessageEntriesTableOrderingComposer
    extends Composer<_$MeridianDatabase, $MessageEntriesTable> {
  $$MessageEntriesTableOrderingComposer({
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

  ColumnOrderings<String> get fromCallsign => $composableBuilder(
    column: $table.fromCallsign,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get addressee => $composableBuilder(
    column: $table.addressee,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isOutgoing => $composableBuilder(
    column: $table.isOutgoing,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get wireId => $composableBuilder(
    column: $table.wireId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupName => $composableBuilder(
    column: $table.groupName,
    builder: (column) => ColumnOrderings(column),
  );

  $$ConversationsTableOrderingComposer get conversationPeer {
    final $$ConversationsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationPeer,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.peerCallsign,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableOrderingComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessageEntriesTableAnnotationComposer
    extends Composer<_$MeridianDatabase, $MessageEntriesTable> {
  $$MessageEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get fromCallsign => $composableBuilder(
    column: $table.fromCallsign,
    builder: (column) => column,
  );

  GeneratedColumn<String> get addressee =>
      $composableBuilder(column: $table.addressee, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<int> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<bool> get isOutgoing => $composableBuilder(
    column: $table.isOutgoing,
    builder: (column) => column,
  );

  GeneratedColumn<String> get wireId =>
      $composableBuilder(column: $table.wireId, builder: (column) => column);

  GeneratedColumnWithTypeConverter<MessageStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<MessageCategory, String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get groupName =>
      $composableBuilder(column: $table.groupName, builder: (column) => column);

  $$ConversationsTableAnnotationComposer get conversationPeer {
    final $$ConversationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationPeer,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.peerCallsign,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableAnnotationComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessageEntriesTableTableManager
    extends
        RootTableManager<
          _$MeridianDatabase,
          $MessageEntriesTable,
          MessageEntryRow,
          $$MessageEntriesTableFilterComposer,
          $$MessageEntriesTableOrderingComposer,
          $$MessageEntriesTableAnnotationComposer,
          $$MessageEntriesTableCreateCompanionBuilder,
          $$MessageEntriesTableUpdateCompanionBuilder,
          (MessageEntryRow, $$MessageEntriesTableReferences),
          MessageEntryRow,
          PrefetchHooks Function({bool conversationPeer})
        > {
  $$MessageEntriesTableTableManager(
    _$MeridianDatabase db,
    $MessageEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessageEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessageEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessageEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> conversationPeer = const Value.absent(),
                Value<String?> fromCallsign = const Value.absent(),
                Value<String?> addressee = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<int> timestamp = const Value.absent(),
                Value<bool> isOutgoing = const Value.absent(),
                Value<String?> wireId = const Value.absent(),
                Value<MessageStatus> status = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<MessageCategory> category = const Value.absent(),
                Value<String?> groupName = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessageEntriesCompanion(
                id: id,
                conversationPeer: conversationPeer,
                fromCallsign: fromCallsign,
                addressee: addressee,
                body: body,
                timestamp: timestamp,
                isOutgoing: isOutgoing,
                wireId: wireId,
                status: status,
                retryCount: retryCount,
                category: category,
                groupName: groupName,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String conversationPeer,
                Value<String?> fromCallsign = const Value.absent(),
                Value<String?> addressee = const Value.absent(),
                required String body,
                required int timestamp,
                required bool isOutgoing,
                Value<String?> wireId = const Value.absent(),
                required MessageStatus status,
                Value<int> retryCount = const Value.absent(),
                required MessageCategory category,
                Value<String?> groupName = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessageEntriesCompanion.insert(
                id: id,
                conversationPeer: conversationPeer,
                fromCallsign: fromCallsign,
                addressee: addressee,
                body: body,
                timestamp: timestamp,
                isOutgoing: isOutgoing,
                wireId: wireId,
                status: status,
                retryCount: retryCount,
                category: category,
                groupName: groupName,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$MessageEntriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({conversationPeer = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (conversationPeer) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.conversationPeer,
                                referencedTable: $$MessageEntriesTableReferences
                                    ._conversationPeerTable(db),
                                referencedColumn:
                                    $$MessageEntriesTableReferences
                                        ._conversationPeerTable(db)
                                        .peerCallsign,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$MessageEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$MeridianDatabase,
      $MessageEntriesTable,
      MessageEntryRow,
      $$MessageEntriesTableFilterComposer,
      $$MessageEntriesTableOrderingComposer,
      $$MessageEntriesTableAnnotationComposer,
      $$MessageEntriesTableCreateCompanionBuilder,
      $$MessageEntriesTableUpdateCompanionBuilder,
      (MessageEntryRow, $$MessageEntriesTableReferences),
      MessageEntryRow,
      PrefetchHooks Function({bool conversationPeer})
    >;
typedef $$GroupMessageEntriesTableCreateCompanionBuilder =
    GroupMessageEntriesCompanion Function({
      required String id,
      required String groupName,
      required String fromCallsign,
      required String body,
      required int timestamp,
      Value<int> rowid,
    });
typedef $$GroupMessageEntriesTableUpdateCompanionBuilder =
    GroupMessageEntriesCompanion Function({
      Value<String> id,
      Value<String> groupName,
      Value<String> fromCallsign,
      Value<String> body,
      Value<int> timestamp,
      Value<int> rowid,
    });

class $$GroupMessageEntriesTableFilterComposer
    extends Composer<_$MeridianDatabase, $GroupMessageEntriesTable> {
  $$GroupMessageEntriesTableFilterComposer({
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

  ColumnFilters<String> get groupName => $composableBuilder(
    column: $table.groupName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fromCallsign => $composableBuilder(
    column: $table.fromCallsign,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );
}

class $$GroupMessageEntriesTableOrderingComposer
    extends Composer<_$MeridianDatabase, $GroupMessageEntriesTable> {
  $$GroupMessageEntriesTableOrderingComposer({
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

  ColumnOrderings<String> get groupName => $composableBuilder(
    column: $table.groupName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fromCallsign => $composableBuilder(
    column: $table.fromCallsign,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GroupMessageEntriesTableAnnotationComposer
    extends Composer<_$MeridianDatabase, $GroupMessageEntriesTable> {
  $$GroupMessageEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get groupName =>
      $composableBuilder(column: $table.groupName, builder: (column) => column);

  GeneratedColumn<String> get fromCallsign => $composableBuilder(
    column: $table.fromCallsign,
    builder: (column) => column,
  );

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<int> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);
}

class $$GroupMessageEntriesTableTableManager
    extends
        RootTableManager<
          _$MeridianDatabase,
          $GroupMessageEntriesTable,
          GroupMessageEntryRow,
          $$GroupMessageEntriesTableFilterComposer,
          $$GroupMessageEntriesTableOrderingComposer,
          $$GroupMessageEntriesTableAnnotationComposer,
          $$GroupMessageEntriesTableCreateCompanionBuilder,
          $$GroupMessageEntriesTableUpdateCompanionBuilder,
          (
            GroupMessageEntryRow,
            BaseReferences<
              _$MeridianDatabase,
              $GroupMessageEntriesTable,
              GroupMessageEntryRow
            >,
          ),
          GroupMessageEntryRow,
          PrefetchHooks Function()
        > {
  $$GroupMessageEntriesTableTableManager(
    _$MeridianDatabase db,
    $GroupMessageEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GroupMessageEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GroupMessageEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$GroupMessageEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> groupName = const Value.absent(),
                Value<String> fromCallsign = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<int> timestamp = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GroupMessageEntriesCompanion(
                id: id,
                groupName: groupName,
                fromCallsign: fromCallsign,
                body: body,
                timestamp: timestamp,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String groupName,
                required String fromCallsign,
                required String body,
                required int timestamp,
                Value<int> rowid = const Value.absent(),
              }) => GroupMessageEntriesCompanion.insert(
                id: id,
                groupName: groupName,
                fromCallsign: fromCallsign,
                body: body,
                timestamp: timestamp,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$GroupMessageEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$MeridianDatabase,
      $GroupMessageEntriesTable,
      GroupMessageEntryRow,
      $$GroupMessageEntriesTableFilterComposer,
      $$GroupMessageEntriesTableOrderingComposer,
      $$GroupMessageEntriesTableAnnotationComposer,
      $$GroupMessageEntriesTableCreateCompanionBuilder,
      $$GroupMessageEntriesTableUpdateCompanionBuilder,
      (
        GroupMessageEntryRow,
        BaseReferences<
          _$MeridianDatabase,
          $GroupMessageEntriesTable,
          GroupMessageEntryRow
        >,
      ),
      GroupMessageEntryRow,
      PrefetchHooks Function()
    >;
typedef $$BulletinsTableCreateCompanionBuilder =
    BulletinsCompanion Function({
      required String sourceCallsign,
      required String addressee,
      required String body,
      required int firstHeardAt,
      required int lastHeardAt,
      Value<int> heardCount,
      required BulletinCategory category,
      required String lineNumber,
      Value<String?> groupName,
      Value<Set<BulletinTransport>> transports,
      Value<double?> receivedLat,
      Value<double?> receivedLon,
      Value<bool> isRead,
      Value<int> rowid,
    });
typedef $$BulletinsTableUpdateCompanionBuilder =
    BulletinsCompanion Function({
      Value<String> sourceCallsign,
      Value<String> addressee,
      Value<String> body,
      Value<int> firstHeardAt,
      Value<int> lastHeardAt,
      Value<int> heardCount,
      Value<BulletinCategory> category,
      Value<String> lineNumber,
      Value<String?> groupName,
      Value<Set<BulletinTransport>> transports,
      Value<double?> receivedLat,
      Value<double?> receivedLon,
      Value<bool> isRead,
      Value<int> rowid,
    });

class $$BulletinsTableFilterComposer
    extends Composer<_$MeridianDatabase, $BulletinsTable> {
  $$BulletinsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sourceCallsign => $composableBuilder(
    column: $table.sourceCallsign,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get addressee => $composableBuilder(
    column: $table.addressee,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get firstHeardAt => $composableBuilder(
    column: $table.firstHeardAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastHeardAt => $composableBuilder(
    column: $table.lastHeardAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get heardCount => $composableBuilder(
    column: $table.heardCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<BulletinCategory, BulletinCategory, String>
  get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get lineNumber => $composableBuilder(
    column: $table.lineNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupName => $composableBuilder(
    column: $table.groupName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<
    Set<BulletinTransport>,
    Set<BulletinTransport>,
    String
  >
  get transports => $composableBuilder(
    column: $table.transports,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<double> get receivedLat => $composableBuilder(
    column: $table.receivedLat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get receivedLon => $composableBuilder(
    column: $table.receivedLon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isRead => $composableBuilder(
    column: $table.isRead,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BulletinsTableOrderingComposer
    extends Composer<_$MeridianDatabase, $BulletinsTable> {
  $$BulletinsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sourceCallsign => $composableBuilder(
    column: $table.sourceCallsign,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get addressee => $composableBuilder(
    column: $table.addressee,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get firstHeardAt => $composableBuilder(
    column: $table.firstHeardAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastHeardAt => $composableBuilder(
    column: $table.lastHeardAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get heardCount => $composableBuilder(
    column: $table.heardCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lineNumber => $composableBuilder(
    column: $table.lineNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupName => $composableBuilder(
    column: $table.groupName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get transports => $composableBuilder(
    column: $table.transports,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get receivedLat => $composableBuilder(
    column: $table.receivedLat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get receivedLon => $composableBuilder(
    column: $table.receivedLon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isRead => $composableBuilder(
    column: $table.isRead,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BulletinsTableAnnotationComposer
    extends Composer<_$MeridianDatabase, $BulletinsTable> {
  $$BulletinsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sourceCallsign => $composableBuilder(
    column: $table.sourceCallsign,
    builder: (column) => column,
  );

  GeneratedColumn<String> get addressee =>
      $composableBuilder(column: $table.addressee, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<int> get firstHeardAt => $composableBuilder(
    column: $table.firstHeardAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastHeardAt => $composableBuilder(
    column: $table.lastHeardAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get heardCount => $composableBuilder(
    column: $table.heardCount,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<BulletinCategory, String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get lineNumber => $composableBuilder(
    column: $table.lineNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get groupName =>
      $composableBuilder(column: $table.groupName, builder: (column) => column);

  GeneratedColumnWithTypeConverter<Set<BulletinTransport>, String>
  get transports => $composableBuilder(
    column: $table.transports,
    builder: (column) => column,
  );

  GeneratedColumn<double> get receivedLat => $composableBuilder(
    column: $table.receivedLat,
    builder: (column) => column,
  );

  GeneratedColumn<double> get receivedLon => $composableBuilder(
    column: $table.receivedLon,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isRead =>
      $composableBuilder(column: $table.isRead, builder: (column) => column);
}

class $$BulletinsTableTableManager
    extends
        RootTableManager<
          _$MeridianDatabase,
          $BulletinsTable,
          BulletinRow,
          $$BulletinsTableFilterComposer,
          $$BulletinsTableOrderingComposer,
          $$BulletinsTableAnnotationComposer,
          $$BulletinsTableCreateCompanionBuilder,
          $$BulletinsTableUpdateCompanionBuilder,
          (
            BulletinRow,
            BaseReferences<_$MeridianDatabase, $BulletinsTable, BulletinRow>,
          ),
          BulletinRow,
          PrefetchHooks Function()
        > {
  $$BulletinsTableTableManager(_$MeridianDatabase db, $BulletinsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BulletinsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BulletinsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BulletinsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sourceCallsign = const Value.absent(),
                Value<String> addressee = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<int> firstHeardAt = const Value.absent(),
                Value<int> lastHeardAt = const Value.absent(),
                Value<int> heardCount = const Value.absent(),
                Value<BulletinCategory> category = const Value.absent(),
                Value<String> lineNumber = const Value.absent(),
                Value<String?> groupName = const Value.absent(),
                Value<Set<BulletinTransport>> transports = const Value.absent(),
                Value<double?> receivedLat = const Value.absent(),
                Value<double?> receivedLon = const Value.absent(),
                Value<bool> isRead = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BulletinsCompanion(
                sourceCallsign: sourceCallsign,
                addressee: addressee,
                body: body,
                firstHeardAt: firstHeardAt,
                lastHeardAt: lastHeardAt,
                heardCount: heardCount,
                category: category,
                lineNumber: lineNumber,
                groupName: groupName,
                transports: transports,
                receivedLat: receivedLat,
                receivedLon: receivedLon,
                isRead: isRead,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sourceCallsign,
                required String addressee,
                required String body,
                required int firstHeardAt,
                required int lastHeardAt,
                Value<int> heardCount = const Value.absent(),
                required BulletinCategory category,
                required String lineNumber,
                Value<String?> groupName = const Value.absent(),
                Value<Set<BulletinTransport>> transports = const Value.absent(),
                Value<double?> receivedLat = const Value.absent(),
                Value<double?> receivedLon = const Value.absent(),
                Value<bool> isRead = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BulletinsCompanion.insert(
                sourceCallsign: sourceCallsign,
                addressee: addressee,
                body: body,
                firstHeardAt: firstHeardAt,
                lastHeardAt: lastHeardAt,
                heardCount: heardCount,
                category: category,
                lineNumber: lineNumber,
                groupName: groupName,
                transports: transports,
                receivedLat: receivedLat,
                receivedLon: receivedLon,
                isRead: isRead,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BulletinsTableProcessedTableManager =
    ProcessedTableManager<
      _$MeridianDatabase,
      $BulletinsTable,
      BulletinRow,
      $$BulletinsTableFilterComposer,
      $$BulletinsTableOrderingComposer,
      $$BulletinsTableAnnotationComposer,
      $$BulletinsTableCreateCompanionBuilder,
      $$BulletinsTableUpdateCompanionBuilder,
      (
        BulletinRow,
        BaseReferences<_$MeridianDatabase, $BulletinsTable, BulletinRow>,
      ),
      BulletinRow,
      PrefetchHooks Function()
    >;
typedef $$OutgoingBulletinsTableCreateCompanionBuilder =
    OutgoingBulletinsCompanion Function({
      Value<int> id,
      required String addressee,
      required String body,
      required int intervalSeconds,
      Value<int> transmissionCount,
      Value<int?> expiresAt,
      required int createdAt,
      Value<int?> lastTransmittedAt,
      Value<bool> viaRf,
      Value<bool> viaAprsIs,
      Value<bool> enabled,
    });
typedef $$OutgoingBulletinsTableUpdateCompanionBuilder =
    OutgoingBulletinsCompanion Function({
      Value<int> id,
      Value<String> addressee,
      Value<String> body,
      Value<int> intervalSeconds,
      Value<int> transmissionCount,
      Value<int?> expiresAt,
      Value<int> createdAt,
      Value<int?> lastTransmittedAt,
      Value<bool> viaRf,
      Value<bool> viaAprsIs,
      Value<bool> enabled,
    });

class $$OutgoingBulletinsTableFilterComposer
    extends Composer<_$MeridianDatabase, $OutgoingBulletinsTable> {
  $$OutgoingBulletinsTableFilterComposer({
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

  ColumnFilters<String> get addressee => $composableBuilder(
    column: $table.addressee,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get intervalSeconds => $composableBuilder(
    column: $table.intervalSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get transmissionCount => $composableBuilder(
    column: $table.transmissionCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastTransmittedAt => $composableBuilder(
    column: $table.lastTransmittedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get viaRf => $composableBuilder(
    column: $table.viaRf,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get viaAprsIs => $composableBuilder(
    column: $table.viaAprsIs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OutgoingBulletinsTableOrderingComposer
    extends Composer<_$MeridianDatabase, $OutgoingBulletinsTable> {
  $$OutgoingBulletinsTableOrderingComposer({
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

  ColumnOrderings<String> get addressee => $composableBuilder(
    column: $table.addressee,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get intervalSeconds => $composableBuilder(
    column: $table.intervalSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get transmissionCount => $composableBuilder(
    column: $table.transmissionCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastTransmittedAt => $composableBuilder(
    column: $table.lastTransmittedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get viaRf => $composableBuilder(
    column: $table.viaRf,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get viaAprsIs => $composableBuilder(
    column: $table.viaAprsIs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OutgoingBulletinsTableAnnotationComposer
    extends Composer<_$MeridianDatabase, $OutgoingBulletinsTable> {
  $$OutgoingBulletinsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get addressee =>
      $composableBuilder(column: $table.addressee, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<int> get intervalSeconds => $composableBuilder(
    column: $table.intervalSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<int> get transmissionCount => $composableBuilder(
    column: $table.transmissionCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get lastTransmittedAt => $composableBuilder(
    column: $table.lastTransmittedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get viaRf =>
      $composableBuilder(column: $table.viaRf, builder: (column) => column);

  GeneratedColumn<bool> get viaAprsIs =>
      $composableBuilder(column: $table.viaAprsIs, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);
}

class $$OutgoingBulletinsTableTableManager
    extends
        RootTableManager<
          _$MeridianDatabase,
          $OutgoingBulletinsTable,
          OutgoingBulletinRow,
          $$OutgoingBulletinsTableFilterComposer,
          $$OutgoingBulletinsTableOrderingComposer,
          $$OutgoingBulletinsTableAnnotationComposer,
          $$OutgoingBulletinsTableCreateCompanionBuilder,
          $$OutgoingBulletinsTableUpdateCompanionBuilder,
          (
            OutgoingBulletinRow,
            BaseReferences<
              _$MeridianDatabase,
              $OutgoingBulletinsTable,
              OutgoingBulletinRow
            >,
          ),
          OutgoingBulletinRow,
          PrefetchHooks Function()
        > {
  $$OutgoingBulletinsTableTableManager(
    _$MeridianDatabase db,
    $OutgoingBulletinsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutgoingBulletinsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutgoingBulletinsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutgoingBulletinsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> addressee = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<int> intervalSeconds = const Value.absent(),
                Value<int> transmissionCount = const Value.absent(),
                Value<int?> expiresAt = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int?> lastTransmittedAt = const Value.absent(),
                Value<bool> viaRf = const Value.absent(),
                Value<bool> viaAprsIs = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
              }) => OutgoingBulletinsCompanion(
                id: id,
                addressee: addressee,
                body: body,
                intervalSeconds: intervalSeconds,
                transmissionCount: transmissionCount,
                expiresAt: expiresAt,
                createdAt: createdAt,
                lastTransmittedAt: lastTransmittedAt,
                viaRf: viaRf,
                viaAprsIs: viaAprsIs,
                enabled: enabled,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String addressee,
                required String body,
                required int intervalSeconds,
                Value<int> transmissionCount = const Value.absent(),
                Value<int?> expiresAt = const Value.absent(),
                required int createdAt,
                Value<int?> lastTransmittedAt = const Value.absent(),
                Value<bool> viaRf = const Value.absent(),
                Value<bool> viaAprsIs = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
              }) => OutgoingBulletinsCompanion.insert(
                id: id,
                addressee: addressee,
                body: body,
                intervalSeconds: intervalSeconds,
                transmissionCount: transmissionCount,
                expiresAt: expiresAt,
                createdAt: createdAt,
                lastTransmittedAt: lastTransmittedAt,
                viaRf: viaRf,
                viaAprsIs: viaAprsIs,
                enabled: enabled,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OutgoingBulletinsTableProcessedTableManager =
    ProcessedTableManager<
      _$MeridianDatabase,
      $OutgoingBulletinsTable,
      OutgoingBulletinRow,
      $$OutgoingBulletinsTableFilterComposer,
      $$OutgoingBulletinsTableOrderingComposer,
      $$OutgoingBulletinsTableAnnotationComposer,
      $$OutgoingBulletinsTableCreateCompanionBuilder,
      $$OutgoingBulletinsTableUpdateCompanionBuilder,
      (
        OutgoingBulletinRow,
        BaseReferences<
          _$MeridianDatabase,
          $OutgoingBulletinsTable,
          OutgoingBulletinRow
        >,
      ),
      OutgoingBulletinRow,
      PrefetchHooks Function()
    >;

class $MeridianDatabaseManager {
  final _$MeridianDatabase _db;
  $MeridianDatabaseManager(this._db);
  $$StationsTableTableManager get stations =>
      $$StationsTableTableManager(_db, _db.stations);
  $$PositionHistoryTableTableManager get positionHistory =>
      $$PositionHistoryTableTableManager(_db, _db.positionHistory);
  $$PacketsTableTableManager get packets =>
      $$PacketsTableTableManager(_db, _db.packets);
  $$ConversationsTableTableManager get conversations =>
      $$ConversationsTableTableManager(_db, _db.conversations);
  $$MessageEntriesTableTableManager get messageEntries =>
      $$MessageEntriesTableTableManager(_db, _db.messageEntries);
  $$GroupMessageEntriesTableTableManager get groupMessageEntries =>
      $$GroupMessageEntriesTableTableManager(_db, _db.groupMessageEntries);
  $$BulletinsTableTableManager get bulletins =>
      $$BulletinsTableTableManager(_db, _db.bulletins);
  $$OutgoingBulletinsTableTableManager get outgoingBulletins =>
      $$OutgoingBulletinsTableTableManager(_db, _db.outgoingBulletins);
}
