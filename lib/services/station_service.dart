import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;

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
/// [recentPackets] holds a rolling buffer of the 500 most recently received
/// packets, newest-first.
class StationService {
  static const int _maxRecentPackets = 500;

  final AprsTransport _transport;
  final _parser = AprsParser();

  // Station map — callsign → most-recently-heard Station.
  final _stations = <String, Station>{};

  // Broadcast controllers.
  final _stationController = StreamController<Map<String, Station>>.broadcast();
  final _packetController = StreamController<AprsPacket>.broadcast();

  // Rolling packet buffer (newest at index 0).
  final _recentPackets = <AprsPacket>[];

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

  /// Rolling buffer of the 500 most recently decoded packets, newest first.
  List<AprsPacket> get recentPackets => List.unmodifiable(_recentPackets);

  /// Forwards the transport's connection state stream.
  Stream<ConnectionStatus> get connectionState => _transport.connectionState;

  /// Returns the transport's current [ConnectionStatus] synchronously.
  /// Use this to seed UI state for widgets that subscribe after the connection
  /// has already been established.
  ConnectionStatus get currentConnectionStatus => _transport.currentStatus;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> start() async {
    try {
      await _transport.connect();
    } catch (e) {
      debugPrint('APRS-IS connection failed: $e');
    }
    _transport.lines.listen(
      _handleLine,
      onError: (e) => debugPrint('Transport error: $e'),
      onDone: () => debugPrint('Transport connection closed'),
    );
  }

  void updateFilter(double lat, double lon, {int radiusKm = 150}) {
    final line =
        '#filter r/${lat.toStringAsFixed(2)}/${lon.toStringAsFixed(2)}/$radiusKm\r\n';
    _transport.sendLine(line);
  }

  Future<void> stop() async {
    await _transport.disconnect();
    await _stationController.close();
    await _packetController.close();
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  void _handleLine(String raw) {
    debugPrint(raw);

    // Skip server comment lines — not packets.
    if (raw.isEmpty || raw.startsWith('#')) return;

    final packet = _parser.parse(raw);

    // Add to rolling buffer.
    _recentPackets.insert(0, packet);
    if (_recentPackets.length > _maxRecentPackets) {
      _recentPackets.removeRange(_maxRecentPackets, _recentPackets.length);
    }

    // Emit on packet stream.
    _packetController.add(packet);

    // If this is a position packet, also update the station map.
    if (packet is PositionPacket) {
      debugPrint('PARSED: ${packet.source} @ ${packet.lat}, ${packet.lon}');
      final station = _stationFromPosition(packet);
      _stations[station.callsign] = station;
      _stationController.add(Map.unmodifiable(_stations));
    } else if (packet is MicEPacket) {
      debugPrint('MIC-E: ${packet.source} @ ${packet.lat}, ${packet.lon}');
      final station = _stationFromMicE(packet);
      _stations[station.callsign] = station;
      _stationController.add(Map.unmodifiable(_stations));
    } else if (packet is UnknownPacket) {
      debugPrint('SKIP: ${packet.reason} -- $raw');
    }
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
    );
  }
}
