import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/packet/aprs_packet.dart';
import '../core/packet/aprs_parser.dart';
import '../core/packet/station.dart';
import '../core/transport/aprs_transport.dart' show ConnectionStatus;

/// Service that ingests APRS text lines, decodes them with [AprsParser], and
/// exposes two streams:
///
///   - [packetStream] — every decoded [AprsPacket] (all types)
///   - [stationUpdates] — a snapshot of the station map, updated each time a
///     position packet is received
///
/// Lines are fed via [ingestLine], which is called from [main.dart] for each
/// connection registered in [ConnectionRegistry]. This service has no
/// transport dependency; connection lifecycle is managed by the connection
/// classes and [ConnectionRegistry].
///
/// [recentPackets] holds a rolling buffer of recent packets. The in-session
/// buffer is capped at [_kMaxInMemoryPackets] for performance; time-based
/// pruning ([packetHistoryDays] / [stationHistoryDays]) is applied at load
/// and persist boundaries.
///
/// History is persisted across app restarts. Call [loadPersistedHistory] once
/// after construction (before ingesting any lines) to restore the previous
/// session.
class StationService extends ChangeNotifier {
  // Hard in-session cap — not user-configurable. Keeps RAM bounded during
  // long APRS-IS sessions on busy frequencies. Time-based pruning reduces
  // this further at the persistence boundary.
  static const int _kMaxInMemoryPackets = 5000;

  // SharedPreferences keys.
  static const _keyPacketDays = 'history_packet_days';
  static const _keyStationDays = 'history_station_days';
  static const _keyPacketLog = 'packet_log_v1';
  static const _keyStationHistory = 'station_history_v1';
  static const _keyStationMaxAgeMinutes = 'station_max_age_minutes';
  static const _keyHiddenTypes = 'station_hidden_types';
  static const _keyShowWeatherOverlay = 'show_weather_overlay';
  static const _keyShowTracks = 'show_tracks';
  static const _keyUseImperialUnits = 'use_imperial_units';

  // Weather overlay sub-settings
  static const _keyWeatherRadiusKm = 'weather_overlay_radius_km';
  static const _keyWeatherUseCelsius = 'weather_overlay_use_celsius';
  static const _keyWeatherMaxAgeMinutes = 'weather_overlay_max_age_minutes';

  /// Maximum number of position history entries kept per station.
  static const int _kMaxPositionHistory = 500;

  /// Sentinel value meaning "keep forever" (no age-based pruning).
  static const int forever = 0;

  final _parser = AprsParser();

  // Station map — callsign → most-recently-heard Station.
  final _stations = <String, Station>{};

  // Broadcast controllers.
  final _stationController = StreamController<Map<String, Station>>.broadcast();
  final _packetController = StreamController<AprsPacket>.broadcast();

  // Rolling packet buffer (newest at index 0).
  final _recentPackets = <AprsPacket>[];

  // History age limits (days; 0 = forever).
  int _packetHistoryDays = 30;
  int _stationHistoryDays = 90;

  // Map display filter: max age in minutes; null = no limit. Default: 60 min.
  // This is a VIEW filter only — it does not delete station data. The station
  // map is filtered in the UI layer (map_screen.dart) before building markers.
  int? _stationMaxAgeMinutes = 60;

  // Station type display filter — types in this set are hidden on the map.
  // View filter only; no data is deleted.
  Set<StationType> _hiddenTypes = {};

  // Whether to render movement trail polylines on the map.
  bool _showTracks = false;

  // Whether to display distances in imperial units (miles/feet) instead of
  // metric (km/m).
  bool _useImperialUnits = false;

  // Whether to show the weather overlay chip on the map.
  bool _showWeatherOverlay = false;

  int _weatherOverlayRadiusKm = 50;
  bool _weatherOverlayUseCelsius = false;
  int _weatherOverlayMaxAgeMinutes = 60;

  // Persistence state.
  SharedPreferences? _prefs;
  Timer? _persistTimer;

  StationService();

  // ---------------------------------------------------------------------------
  // Backward-compat stubs (removed in Phase 6 when UI is updated)
  // ---------------------------------------------------------------------------

  /// Always returns [ConnectionStatus.disconnected].
  ///
  /// APRS-IS connection status is now available via [ConnectionRegistry].
  /// This getter is retained for UI compatibility until Phase 6.
  ConnectionStatus get currentConnectionStatus => ConnectionStatus.disconnected;

  /// A stream that never emits.
  ///
  /// APRS-IS connection state is now available via [ConnectionRegistry].
  /// This getter is retained for UI compatibility until Phase 6.
  Stream<ConnectionStatus> get connectionState => const Stream.empty();

  /// No-op. Line ingestion is wired in main.dart via [ConnectionRegistry].
  Future<void> start() async {}

  /// Closes stream controllers and cancels timers.
  Future<void> stop() async {
    _persistTimer?.cancel();
    await _stationController.close();
    await _packetController.close();
  }

  /// No-op. Use [ConnectionRegistry] to access [AprsIsConnection].
  Future<void> connectAprsIs() async {}

  /// No-op. Use [ConnectionRegistry] to access [AprsIsConnection].
  Future<void> disconnectAprsIs() async {}

  /// No-op. Use [AprsIsConnection.updateCredentials] directly.
  void updateAprsIsCredentials({
    required String loginLine,
    String? filterLine,
  }) {}

  /// No-op. Use [AprsIsConnection.updateFilter] directly.
  void updateFilter(double lat, double lon, {int radiusKm = 150}) {}

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// All decoded packets as they arrive.
  Stream<AprsPacket> get packetStream => _packetController.stream;

  /// Station map snapshots. Emitted whenever a position packet updates a
  /// station.
  Stream<Map<String, Station>> get stationUpdates => _stationController.stream;

  /// Current station map (unmodifiable).
  Map<String, Station> get currentStations => Map.unmodifiable(_stations);

  /// Rolling buffer of the most recently decoded packets, newest first.
  List<AprsPacket> get recentPackets => List.unmodifiable(_recentPackets);

  /// Max age of persisted packets in days. [forever] (0) means no age limit.
  int get packetHistoryDays => _packetHistoryDays;

  /// Max age of persisted stations in days. [forever] (0) means no age limit.
  int get stationHistoryDays => _stationHistoryDays;

  /// Max age for the map display filter in minutes. [null] means no limit.
  ///
  /// This is a view filter only — changing it never deletes station data.
  /// The map screen filters [currentStations] by this value before building
  /// markers and polylines. Station data is retained according to
  /// [stationHistoryDays].
  int? get stationMaxAgeMinutes => _stationMaxAgeMinutes;

  /// Update the map station age filter. Set to [null] to disable filtering.
  Future<void> setStationMaxAgeMinutes(int? value) async {
    if (value == _stationMaxAgeMinutes) return;
    _stationMaxAgeMinutes = value;
    if (value == null) {
      await _prefs?.remove(_keyStationMaxAgeMinutes);
    } else {
      await _prefs?.setInt(_keyStationMaxAgeMinutes, value);
    }
    notifyListeners();
  }

  /// Station types currently hidden on the map (display filter, not deletion).
  Set<StationType> get hiddenTypes => Set.unmodifiable(_hiddenTypes);

  /// Whether to render track polylines on the map.
  bool get showTracks => _showTracks;

  /// Update the show-tracks toggle. Persists the selection.
  Future<void> setShowTracks(bool value) async {
    if (_showTracks == value) return;
    _showTracks = value;
    await _prefs?.setBool(_keyShowTracks, value);
    notifyListeners();
  }

  /// Whether distances are displayed in imperial units (mi/ft) rather than
  /// metric (km/m).
  bool get useImperialUnits => _useImperialUnits;

  /// Toggle the distance unit preference. Persists the selection.
  Future<void> setUseImperialUnits(bool value) async {
    if (_useImperialUnits == value) return;
    _useImperialUnits = value;
    await _prefs?.setBool(_keyUseImperialUnits, value);
    notifyListeners();
  }

  /// Whether to show the weather overlay chip on the map.
  bool get showWeatherOverlay => _showWeatherOverlay;

  int get weatherOverlayRadiusKm => _weatherOverlayRadiusKm;
  bool get weatherOverlayUseCelsius => _weatherOverlayUseCelsius;
  int get weatherOverlayMaxAgeMinutes => _weatherOverlayMaxAgeMinutes;

  /// Update the weather overlay toggle. Persists the selection.
  Future<void> setShowWeatherOverlay(bool value) async {
    if (_showWeatherOverlay == value) return;
    _showWeatherOverlay = value;
    await _prefs?.setBool(_keyShowWeatherOverlay, value);
    notifyListeners();
  }

  Future<void> setWeatherOverlayRadiusKm(int km) async {
    if (_weatherOverlayRadiusKm == km) return;
    _weatherOverlayRadiusKm = km;
    await _prefs?.setInt(_keyWeatherRadiusKm, km);
    notifyListeners();
  }

  Future<void> setWeatherOverlayUseCelsius(bool value) async {
    if (_weatherOverlayUseCelsius == value) return;
    _weatherOverlayUseCelsius = value;
    await _prefs?.setBool(_keyWeatherUseCelsius, value);
    notifyListeners();
  }

  Future<void> setWeatherOverlayMaxAgeMinutes(int minutes) async {
    if (_weatherOverlayMaxAgeMinutes == minutes) return;
    _weatherOverlayMaxAgeMinutes = minutes;
    await _prefs?.setInt(_keyWeatherMaxAgeMinutes, minutes);
    notifyListeners();
  }

  /// Update which station types are hidden. Persists the selection.
  Future<void> setHiddenTypes(Set<StationType> types) async {
    _hiddenTypes = Set.of(types);
    await _prefs?.setStringList(
      _keyHiddenTypes,
      types.map((t) => t.name).toList(),
    );
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Ingest
  // ---------------------------------------------------------------------------

  /// Ingest a pre-formatted APRS line from a connection.
  ///
  /// [source] identifies whether the line came from APRS-IS, a BLE TNC, or a
  /// serial TNC. Defaults to [PacketSource.aprsIs].
  void ingestLine(String raw, {PacketSource source = PacketSource.aprsIs}) =>
      _handleLine(raw, source: source);

  // ---------------------------------------------------------------------------
  // History persistence
  // ---------------------------------------------------------------------------

  /// Restore history and limit settings from [prefs]. Call once after
  /// construction, before ingesting any lines.
  Future<void> loadPersistedHistory(SharedPreferences prefs) async {
    _prefs = prefs;

    _packetHistoryDays = prefs.getInt(_keyPacketDays) ?? 30;
    _stationHistoryDays = prefs.getInt(_keyStationDays) ?? 90;
    _stationMaxAgeMinutes = prefs.containsKey(_keyStationMaxAgeMinutes)
        ? prefs.getInt(_keyStationMaxAgeMinutes)
        : 60;
    _hiddenTypes = (prefs.getStringList(_keyHiddenTypes) ?? [])
        .map((n) => StationType.values.where((t) => t.name == n).firstOrNull)
        .whereType<StationType>()
        .toSet();
    _showTracks = prefs.getBool(_keyShowTracks) ?? false;
    _useImperialUnits = prefs.getBool(_keyUseImperialUnits) ?? false;
    _showWeatherOverlay = prefs.getBool(_keyShowWeatherOverlay) ?? false;
    _weatherOverlayRadiusKm = prefs.getInt(_keyWeatherRadiusKm) ?? 50;
    _weatherOverlayUseCelsius = prefs.getBool(_keyWeatherUseCelsius) ?? false;
    _weatherOverlayMaxAgeMinutes = prefs.getInt(_keyWeatherMaxAgeMinutes) ?? 60;

    // Restore station map, skipping entries older than the configured limit.
    final stationsRaw = prefs.getString(_keyStationHistory);
    if (stationsRaw != null) {
      try {
        final list = jsonDecode(stationsRaw) as List<dynamic>;
        for (final item in list) {
          final s = _stationFromJson(item as Map<String, dynamic>);
          if (_withinAge(s.lastHeard, _stationHistoryDays)) {
            _stations[s.callsign] = s;
          }
        }
      } catch (e) {
        debugPrint('StationService: failed to load station history: $e');
      }
      _stationController.add(Map.unmodifiable(_stations));
    }

    // Restore packet log, skipping entries older than the configured limit.
    final packetsRaw = prefs.getString(_keyPacketLog);
    if (packetsRaw != null) {
      try {
        final list = jsonDecode(packetsRaw) as List<dynamic>;
        for (final item in list) {
          final map = item as Map<String, dynamic>;
          final raw = map['raw'] as String;
          // 'tnc' is a legacy alias kept for backward compat with persisted logs.
          final srcStr = map['src'] as String?;
          final src = switch (srcStr) {
            'aprs_is' => PacketSource.aprsIs,
            'tnc' => PacketSource.tnc,
            'ble_tnc' => PacketSource.bleTnc,
            'serial_tnc' => PacketSource.serialTnc,
            _ => PacketSource.aprsIs,
          };
          final tsMs = map['ts'] as int?;
          final receivedAt = tsMs != null
              ? DateTime.fromMillisecondsSinceEpoch(tsMs, isUtc: true)
              : null;
          final packet = _parser.parse(
            raw,
            transportSource: src,
            receivedAt: receivedAt,
          );
          if (_withinAge(packet.receivedAt, _packetHistoryDays)) {
            _recentPackets.add(packet);
          }
        }
      } catch (e) {
        debugPrint('StationService: failed to load packet log: $e');
      }
    }
  }

  /// Update the packet history age limit in days ([forever] = no limit).
  Future<void> setPacketHistoryDays(int days) async {
    if (_packetHistoryDays == days) return;
    _packetHistoryDays = days;
    await _prefs?.setInt(_keyPacketDays, days);
    _recentPackets.removeWhere((p) => !_withinAge(p.receivedAt, days));
    notifyListeners();
    _schedulePersist();
  }

  /// Update the station history age limit in days ([forever] = no limit).
  Future<void> setStationHistoryDays(int days) async {
    if (_stationHistoryDays == days) return;
    _stationHistoryDays = days;
    await _prefs?.setInt(_keyStationDays, days);
    _stations.removeWhere((_, s) => !_withinAge(s.lastHeard, days));
    _stationController.add(Map.unmodifiable(_stations));
    notifyListeners();
    _schedulePersist();
  }

  /// Delete all persisted and in-memory packets.
  Future<void> clearPacketLog() async {
    _recentPackets.clear();
    await _prefs?.remove(_keyPacketLog);
    notifyListeners();
  }

  /// Delete all persisted and in-memory stations.
  Future<void> clearStationHistory() async {
    _stations.clear();
    await _prefs?.remove(_keyStationHistory);
    _stationController.add(Map.unmodifiable(_stations));
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  void _handleLine(String raw, {PacketSource source = PacketSource.aprsIs}) {
    debugPrint(raw);

    if (raw.isEmpty || raw.startsWith('#')) return;

    final packet = _parser.parse(raw, transportSource: source);

    // Add to rolling in-session buffer, capped for performance.
    _recentPackets.insert(0, packet);
    if (_recentPackets.length > _kMaxInMemoryPackets) {
      _recentPackets.removeLast();
    }

    _packetController.add(packet);

    if (packet is PositionPacket) {
      debugPrint('PARSED: ${packet.source} @ ${packet.lat}, ${packet.lon}');
      final station = _mergeStation(_stationFromPosition(packet));
      _stations[station.callsign] = station;
      _stationController.add(Map.unmodifiable(_stations));
    } else if (packet is MicEPacket) {
      debugPrint('MIC-E: ${packet.source} @ ${packet.lat}, ${packet.lon}');
      final station = _mergeStation(_stationFromMicE(packet));
      _stations[station.callsign] = station;
      _stationController.add(Map.unmodifiable(_stations));
    } else if (packet is ObjectPacket) {
      if (!packet.isAlive) {
        if (_stations.remove(packet.objectName) != null) {
          _stationController.add(Map.unmodifiable(_stations));
        }
      } else {
        final station = _mergeStation(_stationFromObject(packet));
        _stations[station.callsign] = station;
        _stationController.add(Map.unmodifiable(_stations));
      }
    } else if (packet is ItemPacket) {
      if (!packet.isAlive) {
        if (_stations.remove(packet.itemName) != null) {
          _stationController.add(Map.unmodifiable(_stations));
        }
      } else {
        final station = _mergeStation(_stationFromItem(packet));
        _stations[station.callsign] = station;
        _stationController.add(Map.unmodifiable(_stations));
      }
    } else if (packet is WeatherPacket) {
      if (packet.lat != null && packet.lon != null) {
        final station = _mergeStation(_stationFromWeather(packet));
        _stations[station.callsign] = station;
        _stationController.add(Map.unmodifiable(_stations));
      }
    } else if (packet is UnknownPacket) {
      debugPrint('SKIP: ${packet.reason} -- $raw');
    }

    _schedulePersist();
  }

  Station _mergeStation(Station incoming) {
    final prev = _stations[incoming.callsign];
    if (prev == null) return incoming;

    // Append the previous position to the history track before overwriting it.
    final newEntry = TimestampedPosition(
      prev.lastHeard,
      LatLng(prev.lat, prev.lon),
    );
    var history = [...prev.positionHistory, newEntry];
    if (history.length > _kMaxPositionHistory) {
      history = history.sublist(history.length - _kMaxPositionHistory);
    }

    return Station(
      callsign: incoming.callsign,
      lat: incoming.lat,
      lon: incoming.lon,
      rawPacket: incoming.rawPacket,
      lastHeard: incoming.lastHeard,
      symbolTable: incoming.symbolTable,
      symbolCode: incoming.symbolCode,
      comment: incoming.comment.isNotEmpty ? incoming.comment : prev.comment,
      device: incoming.device ?? prev.device,
      positionHistory: history,
      type: incoming.type,
    );
  }

  Station _stationFromPosition(PositionPacket p) => Station(
    callsign: p.source,
    lat: p.lat,
    lon: p.lon,
    rawPacket: p.rawLine,
    lastHeard: p.receivedAt,
    symbolTable: p.symbolTable,
    symbolCode: p.symbolCode,
    comment: p.comment,
    device: p.device,
    type: classifyStationType(p.symbolTable, p.symbolCode),
  );

  Station _stationFromMicE(MicEPacket p) => Station(
    callsign: p.source,
    lat: p.lat,
    lon: p.lon,
    rawPacket: p.rawLine,
    lastHeard: p.receivedAt,
    symbolTable: p.symbolTable,
    symbolCode: p.symbolCode,
    comment: p.comment,
    device: p.device,
    type: classifyStationType(p.symbolTable, p.symbolCode),
  );

  Station _stationFromObject(ObjectPacket p) => Station(
    callsign: p.objectName,
    lat: p.lat,
    lon: p.lon,
    rawPacket: p.rawLine,
    lastHeard: p.receivedAt,
    symbolTable: p.symbolTable,
    symbolCode: p.symbolCode,
    comment: p.comment,
    device: p.device,
    type: StationType.object,
  );

  Station _stationFromItem(ItemPacket p) => Station(
    callsign: p.itemName,
    lat: p.lat,
    lon: p.lon,
    rawPacket: p.rawLine,
    lastHeard: p.receivedAt,
    symbolTable: p.symbolTable,
    symbolCode: p.symbolCode,
    comment: p.comment,
    device: p.device,
    type: StationType.object,
  );

  Station _stationFromWeather(WeatherPacket p) => Station(
    callsign: p.source,
    lat: p.lat!,
    lon: p.lon!,
    rawPacket: p.rawLine,
    lastHeard: p.receivedAt,
    symbolTable: p.symbolTable,
    symbolCode: p.symbolCode,
    comment: p.rawLine, // store raw for fallback display
    type: StationType.weather,
  );

  // ---------------------------------------------------------------------------
  // Persistence helpers
  // ---------------------------------------------------------------------------

  bool _withinAge(DateTime dt, int days) {
    if (days == forever) return true;
    return DateTime.now().difference(dt).inDays < days;
  }

  void _schedulePersist() {
    if (_prefs == null) return;
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(seconds: 3), _persistNow);
  }

  void _persistNow() {
    final prefs = _prefs;
    if (prefs == null) return;

    try {
      final stationList = _stations.values
          .where((s) => _withinAge(s.lastHeard, _stationHistoryDays))
          .map(_stationToJson)
          .toList();
      prefs.setString(
        _keyStationHistory,
        jsonEncode(stationList),
      ); // ignore: unawaited_futures
    } catch (e) {
      debugPrint('StationService: failed to persist stations: $e');
    }

    try {
      final packetList = _recentPackets
          .where((p) => _withinAge(p.receivedAt, _packetHistoryDays))
          .map(
            (p) => {
              'raw': p.rawLine,
              'src': switch (p.transportSource) {
                PacketSource.aprsIs => 'aprs_is',
                PacketSource.tnc => 'tnc',
                PacketSource.bleTnc => 'ble_tnc',
                PacketSource.serialTnc => 'serial_tnc',
              },
              'ts': p.receivedAt.millisecondsSinceEpoch,
            },
          )
          .toList();
      prefs.setString(
        _keyPacketLog,
        jsonEncode(packetList),
      ); // ignore: unawaited_futures
    } catch (e) {
      debugPrint('StationService: failed to persist packet log: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Station JSON helpers
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _stationToJson(Station s) => {
    'callsign': s.callsign,
    'lat': s.lat,
    'lon': s.lon,
    'symbolTable': s.symbolTable,
    'symbolCode': s.symbolCode,
    'comment': s.comment,
    'lastHeard': s.lastHeard.millisecondsSinceEpoch,
    'rawPacket': s.rawPacket,
    'type': s.type.name,
    if (s.device != null) 'device': s.device,
    if (s.positionHistory.isNotEmpty)
      'positionHistory': s.positionHistory
          .map(
            (p) => {
              'ts': p.timestamp.millisecondsSinceEpoch,
              'lat': p.position.latitude,
              'lon': p.position.longitude,
            },
          )
          .toList(),
  };

  Station _stationFromJson(Map<String, dynamic> json) {
    final symbolTable = json['symbolTable'] as String;
    final symbolCode = json['symbolCode'] as String;
    final typeStr = json['type'] as String?;
    final type = typeStr != null
        ? StationType.values.where((t) => t.name == typeStr).firstOrNull ??
              classifyStationType(symbolTable, symbolCode)
        : classifyStationType(symbolTable, symbolCode);

    final historyRaw = json['positionHistory'] as List<dynamic>?;
    final positionHistory =
        historyRaw?.map((e) {
          final m = e as Map<String, dynamic>;
          return TimestampedPosition(
            DateTime.fromMillisecondsSinceEpoch(m['ts'] as int, isUtc: true),
            LatLng((m['lat'] as num).toDouble(), (m['lon'] as num).toDouble()),
          );
        }).toList() ??
        const [];

    return Station(
      callsign: json['callsign'] as String,
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      symbolTable: symbolTable,
      symbolCode: symbolCode,
      comment: (json['comment'] as String?) ?? '',
      lastHeard: DateTime.fromMillisecondsSinceEpoch(json['lastHeard'] as int),
      rawPacket: (json['rawPacket'] as String?) ?? '',
      device: json['device'] as String?,
      type: type,
      positionHistory: positionHistory,
    );
  }
}
