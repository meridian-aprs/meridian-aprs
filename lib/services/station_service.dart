import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;

import '../core/packet/position_parser.dart';
import '../core/packet/result.dart';
import '../core/packet/station.dart';
import '../core/transport/aprs_transport.dart';

class StationService {
  final AprsTransport _transport;
  final _stations = <String, Station>{};
  final _controller = StreamController<Map<String, Station>>.broadcast();

  StationService(this._transport);

  Stream<Map<String, Station>> get stationUpdates => _controller.stream;
  Map<String, Station> get currentStations => Map.unmodifiable(_stations);

  Future<void> start() async {
    await _transport.connect();
    _transport.lines.listen(_handleLine);
  }

  Future<void> stop() async {
    await _transport.disconnect();
    await _controller.close();
  }

  void _handleLine(String raw) {
    debugPrint(raw);
    final result = parseAprsLine(raw);
    if (result is Ok<Station>) {
      _stations[result.value.callsign] = result.value;
      _controller.add(Map.unmodifiable(_stations));
    }
  }
}
