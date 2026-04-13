/// Utilities for formatting distances in either metric or imperial units.
///
/// Internal storage throughout the app is always in kilometres. These helpers
/// convert to the user-preferred unit at the display boundary.
library;

/// Converts kilometres to miles.
double kmToMiles(double km) => km * 0.621371;

/// Converts miles to kilometres.
double milesToKm(double miles) => miles / 0.621371;

/// Formats a distance (given in km) as a human-readable string, e.g.
/// "14.3 km away", "9 mi away", or "320 m away" / "1050 ft away".
String formatDistance(double km, {required bool imperial}) {
  if (imperial) {
    final mi = kmToMiles(km);
    if (mi < 0.1) return '${(mi * 5280).round()} ft away';
    if (mi < 10.0) return '${mi.toStringAsFixed(1)} mi away';
    return '${mi.round()} mi away';
  } else {
    if (km < 1.0) return '${(km * 1000).round()} m away';
    if (km < 10.0) return '${km.toStringAsFixed(1)} km away';
    return '${km.round()} km away';
  }
}

/// Formats a radius (given in km as an integer) for compact display, e.g.
/// "50 km" or "31 mi". Used in the settings UI for the WX search radius.
String formatRadiusKm(int km, {required bool imperial}) {
  if (!imperial) return '$km km';
  final mi = kmToMiles(km.toDouble());
  if (mi < 10) return '${mi.toStringAsFixed(0)} mi';
  return '${mi.round()} mi';
}
