import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// Abstraction over tile URL construction and network delivery.
///
/// [tileUrl] returns the URL template for a given brightness.
/// [buildTileProvider] returns the flutter_map [TileProvider] to use —
/// implementations must return the **same cached instance** on repeated calls
/// to avoid creating new Dio/HTTP connections on every widget rebuild.
/// [dispose] releases any underlying HTTP client resources.
abstract class MeridianTileProvider {
  String tileUrl(Brightness brightness);
  TileProvider buildTileProvider();
  void dispose() {}
}
