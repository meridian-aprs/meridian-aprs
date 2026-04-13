/// Maidenhead grid locator utilities for ham radio position display.
library;

/// Computes the 6-character Maidenhead grid square locator for a position.
///
/// Examples:
/// - New York City (40.71° N, 74.01° W) → FN20xr
/// - London (51.51° N, 0.13° W)         → IO91wm
String maidenheadLocator(double lat, double lon) {
  final lonAdj = lon + 180.0;
  final latAdj = lat + 90.0;
  final f1 = String.fromCharCode(65 + (lonAdj / 20).floor());
  final f2 = String.fromCharCode(65 + (latAdj / 10).floor());
  final s1 = ((lonAdj % 20) / 2).floor();
  final s2 = (latAdj % 10).floor();
  final ss1 = String.fromCharCode(97 + ((lonAdj % 2) * 12).floor());
  final ss2 = String.fromCharCode(97 + ((latAdj % 1) * 24).floor());
  return '$f1$f2$s1$s2$ss1$ss2';
}
