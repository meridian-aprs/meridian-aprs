import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/connection/connection_registry.dart';
import '../core/packet/aprs_packet.dart';
import '../core/packet/aprs_parser.dart';
import '../core/packet/station.dart';
import '../core/util/clock.dart';
import '../database/daos/packet_dao.dart';
import '../database/daos/station_dao.dart';
import '../database/meridian_database.dart';
import '../database/tables/packets.dart' show PacketTypeTag;

/// Service that ingests APRS text lines, decodes them with [AprsParser], and
/// persists stations + packets to the drift database (ADR-062).
///
/// Reads are served from in-memory caches kept in sync with the database via
/// drift `watch()` subscriptions plus immediate write-through updates from
/// main-isolate ingests. The synchronous [currentStations] and [recentPackets]
/// getters are preserved for the existing UI layer.
///
/// Settings (retention windows, display toggles, weather overlay) continue to
/// live in `SharedPreferences` — only structured packet/station data has moved
/// to SQLite. Call [loadPersistedSettings] once after construction (before
/// [attach]) to restore those preferences.
class StationService extends ChangeNotifier {
  // Hard in-session cap on the cached packet snapshot. Keeps RAM bounded and
  // matches the previous in-memory rolling-buffer behaviour. Time-based
  // pruning of the underlying `packets` table is governed by
  // [packetHistoryDays] via the 60-second prune timer.
  static const int _kMaxInMemoryPackets = 5000;

  /// Maximum number of position-history entries kept per station. Enforced
  /// inside the upsert transaction.
  static const int _kMaxPositionHistory = 500;

  /// Sentinel meaning "keep forever" (no age-based pruning).
  static const int forever = 0;

  // SharedPreferences keys — settings only. Structured data lives in drift.
  static const _keyPacketDays = 'history_packet_days';
  static const _keyStationDays = 'history_station_days';
  static const _keyStationMaxAgeMinutes = 'station_max_age_minutes';
  static const _keyHiddenTypes = 'station_hidden_types';
  static const _keyShowWeatherOverlay = 'show_weather_overlay';
  static const _keyShowTracks = 'show_tracks';
  static const _keyUseImperialUnits = 'use_imperial_units';
  static const _keyWeatherRadiusKm = 'weather_overlay_radius_km';
  static const _keyWeatherUseCelsius = 'weather_overlay_use_celsius';
  static const _keyWeatherMaxAgeMinutes = 'weather_overlay_max_age_minutes';

  StationService({
    required StationDao stationDao,
    required PacketDao packetDao,
    Clock clock = DateTime.now,
  }) : _stationDao = stationDao,
       _packetDao = packetDao,
       _clock = clock {
    // asyncMap serialises handling: _onStationsRowsChanged awaits a position-
    // history read, so a plain listen() would let two close-spaced emissions
    // overlap and a slow earlier handler could clobber _stationCache with stale
    // data. asyncMap waits for each handler before delivering the next event.
    _stationsSub = _stationDao
        .watchAllStations()
        .asyncMap(_onStationsRowsChanged)
        .listen((_) {});
    _packetsSub = _packetDao
        .watchRecent(limit: _kMaxInMemoryPackets)
        .listen(_onPacketsRowsChanged);
    // Prune timer is started in [attach] — unit and widget tests that build
    // the service without wiring a registry don't need a 60 s timer hanging
    // around the framework's pending-timer check.
  }

  final StationDao _stationDao;
  final PacketDao _packetDao;
  final Clock _clock;
  final _parser = AprsParser();

  // Snapshot caches served by sync getters.
  Map<String, Station> _stationCache = {};
  List<AprsPacket> _packetCache = [];

  // Broadcast streams (separate from drift `watch()` so packetStream fires
  // synchronously on parse — required by `MessageService._onPacket` and the
  // existing UI listeners).
  final _packetController = StreamController<AprsPacket>.broadcast();
  final _stationController = StreamController<Map<String, Station>>.broadcast();

  // Active drift watch subscriptions.
  StreamSubscription<void>? _stationsSub;
  StreamSubscription<List<PacketRow>>? _packetsSub;

  // Single in-flight ingest serialises the "read prev → merge → write" chain
  // so two close-spaced position packets for the same callsign cannot race on
  // their merged position-history.
  Future<void> _ingestChain = Future.value();

  // Periodic retention prune; falls back to a no-op while `_prefs` is null.
  Timer? _pruneTimer;

  // Active subscription to ConnectionRegistry.lines, set by [attach].
  StreamSubscription<({String line, ConnectionType source})>? _registrySub;

  SharedPreferences? _prefs;

  // History age limits (days; [forever] = no limit).
  int _packetHistoryDays = 30;
  int _stationHistoryDays = 90;

  // Map display filter — view filter only, no data deletion.
  int? _stationMaxAgeMinutes = 60;

  // Display toggles — view filters only.
  Set<StationType> _hiddenTypes = {};
  bool _showTracks = true;
  bool _useImperialUnits = false;
  bool _showWeatherOverlay = false;
  int _weatherOverlayRadiusKm = 50;
  bool _weatherOverlayUseCelsius = false;
  int _weatherOverlayMaxAgeMinutes = 60;

  // ---------------------------------------------------------------------------
  // Backward-compat stubs (kept until v0.20 UI cleanup)
  // ---------------------------------------------------------------------------

  /// Always returns [ConnectionStatus.disconnected].
  /// APRS-IS connection state lives on [ConnectionRegistry] now.
  ConnectionStatus get currentConnectionStatus => ConnectionStatus.disconnected;

  /// Always-empty stream — kept for UI compatibility.
  Stream<ConnectionStatus> get connectionState => const Stream.empty();

  /// No-op. Line ingestion is wired in main.dart via [ConnectionRegistry].
  Future<void> start() async {}

  /// Cancels watch subscriptions, prune timer, registry subscription, and
  /// closes the broadcast controllers. Idempotent.
  Future<void> stop() async {
    _pruneTimer?.cancel();
    _pruneTimer = null;
    await _registrySub?.cancel();
    _registrySub = null;
    await _stationsSub?.cancel();
    _stationsSub = null;
    await _packetsSub?.cancel();
    _packetsSub = null;
    if (!_stationController.isClosed) await _stationController.close();
    if (!_packetController.isClosed) await _packetController.close();
  }

  @override
  void dispose() {
    unawaited(stop());
    super.dispose();
  }

  /// No-op. Use [ConnectionRegistry] to access [AprsIsConnection].
  Future<void> connectAprsIs() async {}

  /// No-op. Use [ConnectionRegistry] to access [AprsIsConnection].
  Future<void> disconnectAprsIs() async {}

  /// No-op. Use [AprsIsConnection.setCredentials] directly.
  void updateAprsIsCredentials({
    required String loginLine,
    String? filterLine,
  }) {}

  /// No-op. Use [AprsIsConnection.updateFilter] directly.
  void updateFilter(double lat, double lon, {int radiusKm = 150}) {}

  // ---------------------------------------------------------------------------
  // Public API — reads
  // ---------------------------------------------------------------------------

  /// All decoded packets as they arrive (sync emission on parse).
  Stream<AprsPacket> get packetStream => _packetController.stream;

  /// Station map snapshots. Fires whenever a position-like packet updates a
  /// station, or whenever the drift watch stream reports a change (e.g.
  /// background-isolate write).
  Stream<Map<String, Station>> get stationUpdates => _stationController.stream;

  /// Current station map (unmodifiable snapshot of the cache).
  Map<String, Station> get currentStations => Map.unmodifiable(_stationCache);

  /// Rolling buffer of the most recently decoded packets, newest first.
  List<AprsPacket> get recentPackets => List.unmodifiable(_packetCache);

  int get packetHistoryDays => _packetHistoryDays;
  int get stationHistoryDays => _stationHistoryDays;
  int? get stationMaxAgeMinutes => _stationMaxAgeMinutes;
  Set<StationType> get hiddenTypes => Set.unmodifiable(_hiddenTypes);
  bool get showTracks => _showTracks;
  bool get useImperialUnits => _useImperialUnits;
  bool get showWeatherOverlay => _showWeatherOverlay;
  int get weatherOverlayRadiusKm => _weatherOverlayRadiusKm;
  bool get weatherOverlayUseCelsius => _weatherOverlayUseCelsius;
  int get weatherOverlayMaxAgeMinutes => _weatherOverlayMaxAgeMinutes;

  // ---------------------------------------------------------------------------
  // Public API — settings (mirror previous SharedPreferences semantics)
  // ---------------------------------------------------------------------------

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

  Future<void> setShowTracks(bool value) async {
    if (_showTracks == value) return;
    _showTracks = value;
    await _prefs?.setBool(_keyShowTracks, value);
    notifyListeners();
  }

  Future<void> setUseImperialUnits(bool value) async {
    if (_useImperialUnits == value) return;
    _useImperialUnits = value;
    await _prefs?.setBool(_keyUseImperialUnits, value);
    notifyListeners();
  }

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

  Future<void> setHiddenTypes(Set<StationType> types) async {
    _hiddenTypes = Set.of(types);
    await _prefs?.setStringList(
      _keyHiddenTypes,
      types.map((t) => t.name).toList(),
    );
    notifyListeners();
  }

  /// Update the packet retention window. Immediately prunes the underlying
  /// `packets` table when shortened.
  Future<void> setPacketHistoryDays(int days) async {
    if (_packetHistoryDays == days) return;
    _packetHistoryDays = days;
    await _prefs?.setInt(_keyPacketDays, days);
    if (days != forever) {
      await _packetDao.pruneOlderThan(_clock().subtract(Duration(days: days)));
    }
    notifyListeners();
  }

  /// Update the station retention window. Immediately prunes the underlying
  /// `stations` table (CASCADE deletes their position history).
  Future<void> setStationHistoryDays(int days) async {
    if (_stationHistoryDays == days) return;
    _stationHistoryDays = days;
    await _prefs?.setInt(_keyStationDays, days);
    if (days != forever) {
      await _stationDao.pruneOlderThan(_clock().subtract(Duration(days: days)));
    }
    notifyListeners();
  }

  /// Delete the entire packet log (drift) and the in-memory cache.
  Future<void> clearPacketLog() async {
    await _packetDao.clearAll();
    _packetCache = const [];
    notifyListeners();
  }

  /// Delete every station and its position history (drift) and clear the
  /// in-memory cache.
  Future<void> clearStationHistory() async {
    await _stationDao.clearAll();
    _stationCache = const {};
    _stationController.add(const {});
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Settings load (no structured data — that comes from drift watch streams)
  // ---------------------------------------------------------------------------

  /// Restore retention windows and display toggles from [prefs]. Call once at
  /// startup, before [attach]. Replaces the v0.18 `loadPersistedHistory` JSON
  /// restore — structured data now lives in drift and hydrates via the
  /// watch streams subscribed in the constructor.
  Future<void> loadPersistedSettings(SharedPreferences prefs) async {
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
    _showTracks = prefs.getBool(_keyShowTracks) ?? true;
    _useImperialUnits = prefs.getBool(_keyUseImperialUnits) ?? false;
    _showWeatherOverlay = prefs.getBool(_keyShowWeatherOverlay) ?? false;
    _weatherOverlayRadiusKm = prefs.getInt(_keyWeatherRadiusKm) ?? 50;
    _weatherOverlayUseCelsius = prefs.getBool(_keyWeatherUseCelsius) ?? false;
    _weatherOverlayMaxAgeMinutes = prefs.getInt(_keyWeatherMaxAgeMinutes) ?? 60;
  }

  // ---------------------------------------------------------------------------
  // Ingest
  // ---------------------------------------------------------------------------

  /// Subscribe to [registry]'s multiplexed lines stream. Single production
  /// ingestion seam. Calling twice is a programming error.
  void attach(ConnectionRegistry registry) {
    assert(
      _registrySub == null,
      'StationService.attach called twice; a single subscription is expected.',
    );
    _registrySub = registry.lines.listen((event) {
      // Fire-and-forget — `_handleLine` serialises internally so cache merges
      // stay consistent regardless of how fast the registry pushes events.
      unawaited(
        _handleLine(event.line, source: _packetSourceFor(event.source)),
      );
    });
    _pruneTimer ??= Timer.periodic(
      const Duration(seconds: 60),
      (_) => unawaited(_runPrune()),
    );
  }

  /// Ingest a pre-formatted APRS line. Returns a future that completes once
  /// the packet (and any station update) has been persisted to drift and the
  /// snapshot caches reflect the new state. Tests should `await` this.
  Future<void> ingestLine(
    String raw, {
    PacketSource source = PacketSource.aprsIs,
  }) => _handleLine(raw, source: source);

  /// Record a packet we transmitted, tagged with the transport it went out
  /// on. Mirrors [ingestLine] but flags the row `is_outgoing = true`.
  Future<void> recordOutgoing(String raw, {required PacketSource source}) =>
      _handleLine(raw, source: source, isOutgoing: true);

  static PacketSource _packetSourceFor(ConnectionType type) => switch (type) {
    ConnectionType.aprsIs => PacketSource.aprsIs,
    ConnectionType.bleTnc => PacketSource.bleTnc,
    ConnectionType.serialTnc => PacketSource.serialTnc,
    ConnectionType.classicBtTnc => PacketSource.classicBtTnc,
  };

  Future<void> _handleLine(
    String raw, {
    PacketSource source = PacketSource.aprsIs,
    bool isOutgoing = false,
  }) {
    // Serialise on the per-service ingest chain so position-history merges
    // observe a stable "previous station" snapshot.
    final task = _ingestChain.then(
      (_) => _processLine(raw, source: source, isOutgoing: isOutgoing),
    );
    _ingestChain = task.catchError((Object e, StackTrace st) {
      debugPrint('StationService ingest error: $e\n$st');
    });
    return task;
  }

  Future<void> _processLine(
    String raw, {
    required PacketSource source,
    required bool isOutgoing,
  }) async {
    if (raw.isEmpty || raw.startsWith('#')) return;

    final packet = _parser.parse(
      raw,
      transportSource: source,
      receivedAt: _clock().toUtc(),
    )..isOutgoing = isOutgoing;

    // Synchronous emission — preserves `MessageService._onPacket` semantics.
    _packetController.add(packet);

    // Insert packet row (always). Awaited so ingestLine callers see the new
    // row in `recentPackets` after `await`.
    await _packetDao.insertPacket(
      PacketsCompanion.insert(
        rawLine: raw,
        packetType: _packetTypeTag(packet),
        sourceCallsign: packet.source,
        receivedAt: packet.receivedAt.millisecondsSinceEpoch,
        sourceChannel: source,
        destination: Value(packet.destination),
        isOutgoing: Value(isOutgoing),
      ),
    );

    // Eagerly update the packet cache so sync getters reflect the new packet
    // before the watch stream re-emits.
    _packetCache = [packet, ..._packetCache];
    if (_packetCache.length > _kMaxInMemoryPackets) {
      _packetCache = _packetCache.sublist(0, _kMaxInMemoryPackets);
    }
    notifyListeners();

    // Position-like packets update the station map.
    if (packet is PositionPacket) {
      await _upsertStation(_stationFromPosition(packet));
    } else if (packet is MicEPacket) {
      await _upsertStation(_stationFromMicE(packet));
    } else if (packet is ObjectPacket) {
      if (packet.isAlive) {
        await _upsertStation(_stationFromObject(packet));
      } else {
        await _deleteStation(packet.objectName);
      }
    } else if (packet is ItemPacket) {
      if (packet.isAlive) {
        await _upsertStation(_stationFromItem(packet));
      } else {
        await _deleteStation(packet.itemName);
      }
    } else if (packet is WeatherPacket) {
      if (packet.lat != null && packet.lon != null) {
        await _upsertStation(_stationFromWeather(packet));
      }
    } else if (packet is UnknownPacket) {
      debugPrint('SKIP: ${packet.reason} -- $raw');
    }
  }

  Future<void> _upsertStation(Station incoming) async {
    final prevRow = await _stationDao.getStation(incoming.callsign);
    final prev = prevRow == null
        ? null
        : _stationCache[incoming.callsign] ?? _rowToStation(prevRow, const []);

    final merged = _merge(prev: prev, incoming: incoming);

    PositionHistoryCompanion? prevPos;
    if (prev != null) {
      prevPos = PositionHistoryCompanion.insert(
        callsign: prev.callsign,
        latitude: prev.lat,
        longitude: prev.lon,
        timestamp: prev.lastHeard.millisecondsSinceEpoch,
      );
    }

    await _stationDao.upsertWithPositionHistory(
      station: _stationToCompanion(merged),
      previousPosition: prevPos,
      capHistoryAt: _kMaxPositionHistory,
    );

    _stationCache = Map<String, Station>.from(_stationCache)
      ..[merged.callsign] = merged;
    _stationController.add(Map.unmodifiable(_stationCache));
    notifyListeners();
  }

  Future<void> _deleteStation(String callsign) async {
    final removed = await _stationDao.deleteByCallsign(callsign);
    if (removed == 0) return;
    _stationCache = Map<String, Station>.from(_stationCache)..remove(callsign);
    _stationController.add(Map.unmodifiable(_stationCache));
    notifyListeners();
  }

  Station _merge({required Station? prev, required Station incoming}) {
    if (prev == null) return incoming;

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
      messageCapability: incoming.messageCapability != MessageCapability.unknown
          ? incoming.messageCapability
          : prev.messageCapability,
    );
  }

  // ---------------------------------------------------------------------------
  // Watch stream → cache reconciliation (covers cross-isolate writes)
  // ---------------------------------------------------------------------------

  Future<void> _onStationsRowsChanged(List<StationRow> rows) async {
    final byCallsign = {for (final r in rows) r.callsign: r};
    final allHistory = await _stationDao.getAllPositionHistory();
    final historyByCallsign = <String, List<TimestampedPosition>>{};
    for (final h in allHistory) {
      historyByCallsign
          .putIfAbsent(h.callsign, () => <TimestampedPosition>[])
          .add(
            TimestampedPosition(
              DateTime.fromMillisecondsSinceEpoch(h.timestamp, isUtc: true),
              LatLng(h.latitude, h.longitude),
            ),
          );
    }

    final next = <String, Station>{};
    for (final entry in byCallsign.entries) {
      next[entry.key] = _rowToStation(
        entry.value,
        historyByCallsign[entry.key] ?? const [],
      );
    }
    _stationCache = next;
    _stationController.add(Map.unmodifiable(_stationCache));
    notifyListeners();
  }

  void _onPacketsRowsChanged(List<PacketRow> rows) {
    _packetCache = rows.map(_rowToPacket).toList();
    notifyListeners();
  }

  AprsPacket _rowToPacket(PacketRow row) {
    final packet = _parser.parse(
      row.rawLine,
      transportSource: row.sourceChannel,
      receivedAt: DateTime.fromMillisecondsSinceEpoch(
        row.receivedAt,
        isUtc: true,
      ),
    )..isOutgoing = row.isOutgoing;
    return packet;
  }

  Station _rowToStation(StationRow row, List<TimestampedPosition> history) {
    return Station(
      callsign: row.callsign,
      lat: row.lat,
      lon: row.lon,
      rawPacket: row.rawPacket,
      lastHeard: DateTime.fromMillisecondsSinceEpoch(
        row.lastHeard,
        isUtc: true,
      ),
      symbolTable: row.symbolTable,
      symbolCode: row.symbolCode,
      comment: row.comment,
      device: row.device,
      positionHistory: history,
      type: row.stationType,
      messageCapability: row.messageCapability,
    );
  }

  StationsCompanion _stationToCompanion(Station s) => StationsCompanion.insert(
    callsign: s.callsign,
    symbolTable: s.symbolTable,
    symbolCode: s.symbolCode,
    comment: s.comment,
    rawPacket: s.rawPacket,
    device: Value(s.device),
    lastHeard: s.lastHeard.millisecondsSinceEpoch,
    stationType: s.type,
    messageCapability: s.messageCapability,
    lat: s.lat,
    lon: s.lon,
  );

  PacketTypeTag _packetTypeTag(AprsPacket p) {
    if (p is PositionPacket) return PacketTypeTag.position;
    if (p is WeatherPacket) return PacketTypeTag.weather;
    if (p is MessagePacket) return PacketTypeTag.message;
    if (p is ObjectPacket) return PacketTypeTag.object;
    if (p is ItemPacket) return PacketTypeTag.item;
    if (p is StatusPacket) return PacketTypeTag.status;
    if (p is MicEPacket) return PacketTypeTag.micE;
    if (p is TelemetryPacket) return PacketTypeTag.telemetry;
    if (p is QueryPacket) return PacketTypeTag.query;
    if (p is CapabilitiesPacket) return PacketTypeTag.capabilities;
    return PacketTypeTag.unknown;
  }

  // ---------------------------------------------------------------------------
  // Periodic retention prune
  // ---------------------------------------------------------------------------

  Future<void> _runPrune() async {
    if (_packetHistoryDays != forever) {
      await _packetDao.pruneOlderThan(
        _clock().subtract(Duration(days: _packetHistoryDays)),
      );
    }
    if (_stationHistoryDays != forever) {
      await _stationDao.pruneOlderThan(
        _clock().subtract(Duration(days: _stationHistoryDays)),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Station factories — unchanged from v0.18
  // ---------------------------------------------------------------------------

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
    messageCapability: p.hasMessaging
        ? MessageCapability.supported
        : MessageCapability.unsupported,
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
    messageCapability: MessageCapability.supported,
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
    comment: p.rawLine,
    type: StationType.weather,
  );
}
