import 'dart:async';

import 'package:flutter/services.dart' show MissingPluginException;
import 'package:geolocator/geolocator.dart';
import 'package:meridian_aprs/services/geolocator_adapter.dart';

/// In-memory [GeolocatorAdapter] for tests.
///
/// Defaults to a happy path (service enabled, permission `always`, a fixed
/// stationary fix). Tweak the public flags before invoking the system under
/// test to drive failure paths. Use [emitPosition] / [position] to drive the
/// position stream that smart-mode subscribes to.
class FakeGeolocatorAdapter implements GeolocatorAdapter {
  bool serviceEnabled = true;
  LocationPermission permission = LocationPermission.always;
  bool throwMissingPlugin = false;

  /// Returned by [getCurrentPosition]; defaults to a fixed Austin TX fix.
  Position currentPosition = position();

  /// Counts of each entry point — useful for asserting "no infinite retry".
  int isLocationServiceEnabledCalls = 0;
  int checkPermissionCalls = 0;
  int requestPermissionCalls = 0;
  int getCurrentPositionCalls = 0;
  int getPositionStreamCalls = 0;

  final _streamController = StreamController<Position>.broadcast(sync: true);

  /// Push a position into the stream returned by [getPositionStream].
  void emitPosition(Position p) => _streamController.add(p);

  /// Convenience factory — most fields don't matter for these tests.
  static Position position({
    double lat = 30.27,
    double lon = -97.74,
    double speed = 0,
    double heading = 0,
  }) => Position(
    latitude: lat,
    longitude: lon,
    timestamp: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: heading,
    headingAccuracy: 0,
    speed: speed,
    speedAccuracy: 0,
  );

  @override
  Future<bool> isLocationServiceEnabled() async {
    isLocationServiceEnabledCalls++;
    if (throwMissingPlugin) throw MissingPluginException('no impl');
    return serviceEnabled;
  }

  @override
  Future<LocationPermission> checkPermission() async {
    checkPermissionCalls++;
    if (throwMissingPlugin) throw MissingPluginException('no impl');
    return permission;
  }

  @override
  Future<LocationPermission> requestPermission() async {
    requestPermissionCalls++;
    if (throwMissingPlugin) throw MissingPluginException('no impl');
    return permission;
  }

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    getCurrentPositionCalls++;
    if (throwMissingPlugin) throw MissingPluginException('no impl');
    return currentPosition;
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    getPositionStreamCalls++;
    if (throwMissingPlugin) {
      return Stream.error(MissingPluginException('no impl'));
    }
    return _streamController.stream;
  }

  Future<void> close() => _streamController.close();
}
