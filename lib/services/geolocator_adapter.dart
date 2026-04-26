/// Testability seam over the static `Geolocator` API.
///
/// `BeaconingService` calls platform GPS through this interface so tests can
/// substitute a fake without binding to platform channels. Production wires
/// [RealGeolocatorAdapter], which delegates one-for-one to `geolocator`.
library;

import 'package:geolocator/geolocator.dart';

abstract class GeolocatorAdapter {
  Future<bool> isLocationServiceEnabled();
  Future<LocationPermission> checkPermission();
  Future<LocationPermission> requestPermission();
  Future<Position> getCurrentPosition({LocationSettings? locationSettings});
  Stream<Position> getPositionStream({LocationSettings? locationSettings});
}

class RealGeolocatorAdapter implements GeolocatorAdapter {
  const RealGeolocatorAdapter();

  @override
  Future<bool> isLocationServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  @override
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) =>
      Geolocator.getCurrentPosition(locationSettings: locationSettings);

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      Geolocator.getPositionStream(locationSettings: locationSettings);
}
