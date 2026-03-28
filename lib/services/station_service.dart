import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/packet/aprs_packet.dart';
import '../core/packet/aprs_parser.dart';
import '../core/packet/station.dart';
import '../core/transport/aprs_transport.dart'
    show AprsTransport, ConnectionStatus;

/// Service that ingests raw APRS-IS lines from [AprsTransport], decodes them
/// with [AprsParser], and exposes two streams:
///
///   - [packetStream] — every decoded [AprsPacket] (all types)
///   - [stationUpdates] — a snapshot of the station map, updated each time a
///     position packet is received (backward-compatible with v0.1 UI)
///
/// [recentPackets] holds a rolling buffer of the most recently received
/// packets (configurable via [maxPackets], persisted in SharedPreferences),
/// newest-first.
///
/// History is persisted across app restarts. Call [loadPersistedHistory] once
/// after construction (before [start]) to restore the previous session.
class StationService extends ChangeNotifier {
  static const int _defaultMaxPackets = 500;
  static const int _defaultMaxStations = 1000;

  // SharedPreferences keys.
  static const _keyMaxPackets = 'history_max_packets';
  static const _keyMaxStations = 'history_max_stations';
  static const _keyPacketLog = 'packet_log_v1';
  static const _keyStationHistory = 'station_history_v1';

  final AprsTransport _transport;
  final _parser = AprsParser();

  // Station map — callsign → most-recently-heard Station.
  final _stations = <String, Station>{};

  // Broadcast controllers.
  final _stationController = StreamController<Map<String, Station>>.broadcast();
  final _packetController = StreamController<AprsPacket>.broadcast();

  // Rolling packet buffer (newest at index 0).
  final _recentPackets = <AprsPacket>[];

  // History settings.
  int _maxPackets = _defaultMaxPackets;
  int _maxStations = _defaultMaxStations;

  // Persistence state.
  SharedPreferences? _prefs;
  Timer? _persistTimer;

  StationService(this._transport);

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// All decoded packets as they arrive.
  Stream<AprsPacket> get packetStream => _packetController.stream;

  /// Station map snapshots. Emitted whenever a position packet updates a
  /// station. Backward-compatible with the v0.1 map screen.
  Stream<Map<String, Station>> get stationUpdates => _stationController.stream;

  /// Current station map (unmodifiable).
  Map<String, Station> get currentStations => Map.unmodifiable(_stations);

  /// Rolling buffer of the most recently decoded packets, newest first.
  List<AprsPacket> get recentPackets => List.unmodifiable(_recentPackets);

  /// Forwards the transport's connection state stream.
  Stream<ConnectionStatus> get connectionState => _transport.connectionState;

  /// Returns the transport's current [ConnectionStatus] synchronously.
  ConnectionStatus get currentConnectionStatus => _transport.currentStatus;

  /// Maximum number of packets retained in [recentPackets] and persisted.
  int get maxPackets => _maxPackets;

  /// Maximum number of stations retained in the station map and persisted.
  int get maxStations => _maxStations;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> start() async {
    // Wire up the line stream once — persists across reconnects.
    // Errors are handled inside AprsIsTransport and do not propagate here.
    _transport.lines.listen(_handleLine);
    await connectAprsIs();
  }

  Future<void> connectAprsIs() async {
    try {
      await _transport.connect();
    } catch (e) {
      debugPrint('APRS-IS connection failed: $e');
    }
  }

  Future<void> disconnectAprsIs() async {
    await _transport.disconnect();
  }

  void updateFilter(double lat, double lon, {int radiusKm = 150}) {
    final line =
        '#filter r/${lat.toStringAsFixed(2)}/${lon.toStringAsFixed(2)}/$radiusKm\r\n';
    _transport.sendLine(line);
  }

  /// Ingest a pre-formatted APRS line from an external transport source
  /// (e.g. a TNC). Delegates to [_handleLine].
  void ingestLine(String raw, {PacketSource source = PacketSource.tnc}) =>
      _handleLine(raw, source: source);

  Future<void> stop() async {
    _persistTimer?.cancel();
    await _transport.dispose();
    await _stationController.close();
    await _packetController.close();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // History persistence
  // ---------------------------------------------------------------------------

  /// Restore history and limit settings from [prefs]. Call once after
  /// construction, before [start].
  Future<void> loadPersistedHistory(SharedPreferences prefs) async {
    _prefs = prefs;

    // Load configurable limits.
    _maxPackets = prefs.getInt(_keyMaxPackets) ?? _defaultMaxPackets;
    _maxStations = prefs.getInt(_keyMaxStations) ?? _defaultMaxStations;

    // Restore station map.
    final stationsRaw = prefs.getString(_keyStationHistory);
    if (stationsRaw != null) {
      try {
        final list = jsonDecode(stationsRaw) as List<dynamic>;
        for (final item in list) {
          final s = _stationFromJson(item as Map<String, dynamic>);
          _stations[s.callsign] = s;
        }
      } catch (e) {
        debugPrint('StationService: failed to load station history: $e');
      }
      // Broadcast restored stations to any listeners that subscribed early.
      _stationController.add(Map.unmodifiable(_stations));
    }

    // Restore packet log.
    final packetsRaw = prefs.getString(_keyPacketLog);
    if (packetsRaw != null) {
      try {
        final list = jsonDecode(packetsRaw) as List<dynamic>;
        for (final item in list) {
          final map = item as Map<String, dynamic>;
          final raw = map['raw'] as String;
          final src = map['src'] == 'tnc'
              ? PacketSource.tnc
              : PacketSource.aprsIs;
          final packet = _parser.parse(raw, transportSource: src);
          _recentPackets.add(packet);
        }
      } catch (e) {
        debugPrint('StationService: failed to load packet log: $e');
      }
    }
  }

  /// Update the packet history limit. Trims the in-memory buffer immediately
  /// and schedules a persist.
  Future<void> setMaxPackets(int n) async {
    if (_maxPackets == n) return;
    _maxPackets = n;
    _prefs?.setInt(_keyMaxPackets, n); // ignore: unawaited_futures
    // Trim in-memory buffer.
    if (_recentPackets.length > n) {
      _recentPackets.removeRange(n, _recentPackets.length);
    }
    notifyListeners();
    _schedulePersist();
  }

  /// Update the station history limit. Prunes the oldest stations immediately
  /// and schedules a persist.
  Future<void> setMaxStations(int n) async {
    if (_maxStations == n) return;
    _maxStations = n;
    _prefs?.setInt(_keyMaxStations, n); // ignore: unawaited_futures
    _trimStations();
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

    // Skip server comment lines — not packets.
    if (raw.isEmpty || raw.startsWith('#')) return;

    final packet = _parser.parse(raw, transportSource: source);

    // Add to rolling buffer.
    _recentPackets.insert(0, packet);
    if (_recentPackets.length > _maxPackets) {
      _recentPackets.removeRange(_maxPackets, _recentPackets.length);
    }

    // Emit on packet stream.
    _packetController.add(packet);

    // If this is a position packet, also update the station map.
    if (packet is PositionPacket) {
      debugPrint('PARSED: ${packet.source} @ ${packet.lat}, ${packet.lon}');
      final station = _mergeStation(_stationFromPosition(packet));
      _stations[station.callsign] = station;
      _trimStations();
      _stationController.add(Map.unmodifiable(_stations));
    } else if (packet is MicEPacket) {
      debugPrint('MIC-E: ${packet.source} @ ${packet.lat}, ${packet.lon}');
      final station = _mergeStation(_stationFromMicE(packet));
      _stations[station.callsign] = station;
      _trimStations();
      _stationController.add(Map.unmodifiable(_stations));
    } else if (packet is UnknownPacket) {
      debugPrint('SKIP: ${packet.reason} -- $raw');
    }

    _schedulePersist();
  }

  /// Carry forward non-empty fields from the previous [Station] record for the
  /// same callsign when the incoming station has empty values.
  ///
  /// Currently preserves: comment (never blank out a previously seen comment),
  /// device (keep the last successfully identified device).
  Station _mergeStation(Station incoming) {
    final prev = _stations[incoming.callsign];
    if (prev == null) return incoming;
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
    );
  }

  /// Convert a [PositionPacket] to a [Station] for the legacy station map.
  Station _stationFromPosition(PositionPacket p) {
    return Station(
      callsign: p.source,
      lat: p.lat,
      lon: p.lon,
      rawPacket: p.rawLine,
      lastHeard: p.receivedAt,
      symbolTable: p.symbolTable,
      symbolCode: p.symbolCode,
      comment: p.comment,
      device: p.device,
    );
  }

  /// Convert a [MicEPacket] to a [Station] for the station map.
  Station _stationFromMicE(MicEPacket p) {
    return Station(
      callsign: p.source,
      lat: p.lat,
      lon: p.lon,
      rawPacket: p.rawLine,
      lastHeard: p.receivedAt,
      symbolTable: p.symbolTable,
      symbolCode: p.symbolCode,
      comment: p.comment,
      device: p.device,
    );
  }

  /// Remove the oldest stations if the station map exceeds [_maxStations].
  void _trimStations() {
    if (_stations.length <= _maxStations) return;
    final sorted = _stations.values.toList()
      ..sort((a, b) => a.lastHeard.compareTo(b.lastHeard)); // oldest first
    final excess = _stations.length - _maxStations;
    for (var i = 0; i < excess; i++) {
      _stations.remove(sorted[i].callsign);
    }
  }

  // ---------------------------------------------------------------------------
  // Persistence helpers
  // ---------------------------------------------------------------------------

  /// Schedule a persist 3 seconds after the last call, debounced.
  void _schedulePersist() {
    if (_prefs == null) return;
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(seconds: 3), _persistNow);
  }

  void _persistNow() {
    final prefs = _prefs;
    if (prefs == null) return;

    // Persist station map.
    try {
      final stationList = _stations.values.map(_stationToJson).toList();
      prefs.setString(
        _keyStationHistory,
        jsonEncode(stationList),
      ); // ignore: unawaited_futures
    } catch (e) {
      debugPrint('StationService: failed to persist stations: $e');
    }

    // Persist packet log (raw lines only — re-parsed on load).
    try {
      final packetList = _recentPackets
          .map((p) => {'raw': p.rawLine, 'src': p.transportSource.name})
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
    if (s.device != null) 'device': s.device,
  };

  Station _stationFromJson(Map<String, dynamic> json) => Station(
    callsign: json['callsign'] as String,
    lat: (json['lat'] as num).toDouble(),
    lon: (json['lon'] as num).toDouble(),
    symbolTable: json['symbolTable'] as String,
    symbolCode: json['symbolCode'] as String,
    comment: (json['comment'] as String?) ?? '',
    lastHeard: DateTime.fromMillisecondsSinceEpoch(json['lastHeard'] as int),
    rawPacket: (json['rawPacket'] as String?) ?? '',
    device: json['device'] as String?,
  );
}
