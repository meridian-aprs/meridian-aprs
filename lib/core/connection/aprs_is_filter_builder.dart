/// Builds APRS-IS `#filter` lines from Meridian's viewport + subscription
/// state. Extracted from [AprsIsConnection] in v0.17 PR 5 so the filter
/// composition is testable in isolation and can grow as new filter clauses
/// (groups, station types, etc.) are added without turning `updateFilter`
/// into a 100-line method.
///
/// Filter line shape:
/// ```
/// #filter a/N/W/S/E g/BLN0/BLN1/…/BLN9 g/BLN*WX g/BLN*EMCOMM
/// ```
///
/// The `a/` area clause always comes first (bounding box from the map
/// viewport). The `g/` group clauses always include the 10 general bulletin
/// addressees (`BLN0`–`BLN9`) so the operator's bulletin feed is populated
/// regardless of viewport — client-side radius filtering in [BulletinService]
/// narrows to the user's distance preference. Each subscribed named-bulletin
/// group adds a wildcard clause `g/BLN*NAME` per ADR-058.
///
/// See ADR-033 (area filter), ADR-058 (bulletin scope + group filter extension).
library;

import 'dart:math' show min, max;

import 'aprs_is_filter_config.dart';
import 'lat_lng_box.dart';

abstract final class AprsIsFilterBuilder {
  /// Kilometres per degree of latitude — flat-earth approximation used
  /// throughout the filter math. Must match [AprsIsConnection] so the
  /// Regional preset stays bit-identical across refactors (see ADR-033).
  static const double kmPerDegree = 111.0;

  /// General-bulletin addressees always included in the filter. Named
  /// bulletin groups (`BLN*NAME`) are appended on top via [namedBulletinGroups].
  static const List<String> generalBulletinAddressees = [
    'BLN0',
    'BLN1',
    'BLN2',
    'BLN3',
    'BLN4',
    'BLN5',
    'BLN6',
    'BLN7',
    'BLN8',
    'BLN9',
  ];

  /// Compose the full `#filter …\r\n` line. The returned string already
  /// includes the leading `#filter ` and trailing CRLF so it can go straight
  /// to [AprsIsTransport.sendLine].
  static String buildFilterLine({
    required LatLngBox box,
    required AprsIsFilterConfig config,
    List<String> namedBulletinGroups = const [],
  }) {
    final area = _buildAreaClause(box, config);
    final general = 'g/${generalBulletinAddressees.join('/')}';
    final named = namedBulletinGroups
        .map((n) => n.toUpperCase())
        .where(_isValidNamedGroup)
        .toSet() // dedupe
        .map((n) => 'g/BLN*$n')
        .join(' ');

    final clauses = [area, general, if (named.isNotEmpty) named];
    return '#filter ${clauses.join(' ')}\r\n';
  }

  /// Compose a no-viewport default filter line centred on [lat]/[lon]. Uses
  /// a 167 km floor on the half-extent so "Local" doesn't collapse the
  /// initial feed to 25 km (parity with the pre-refactor
  /// `AprsIsConnection.defaultFilterLine`). The area clause is built directly
  /// from `(lat±half)` without the pad-percentage / min-radius logic — those
  /// apply to viewport-driven filters only.
  static String buildDefaultFilterLine({
    required double lat,
    required double lon,
    required AprsIsFilterConfig config,
    List<String> namedBulletinGroups = const [],
  }) {
    final km = config.minRadiusKm < 167.0 ? 167.0 : config.minRadiusKm;
    final half = km / kmPerDegree;
    final n = (lat + half).clamp(-90.0, 90.0);
    final s = (lat - half).clamp(-90.0, 90.0);
    final w = lon - half;
    final e = lon + half;
    final area =
        'a/${n.toStringAsFixed(2)}/${w.toStringAsFixed(2)}'
        '/${s.toStringAsFixed(2)}/${e.toStringAsFixed(2)}';
    final general = 'g/${generalBulletinAddressees.join('/')}';
    final named = namedBulletinGroups
        .map((n) => n.toUpperCase())
        .where(_isValidNamedGroup)
        .toSet()
        .map((n) => 'g/BLN*$n')
        .join(' ');

    final clauses = [area, general, if (named.isNotEmpty) named];
    return '#filter ${clauses.join(' ')}\r\n';
  }

  static String _buildAreaClause(LatLngBox box, AprsIsFilterConfig config) {
    final latPad = (box.north - box.south) * config.padPct;
    final lonPad = (box.east - box.west) * config.padPct;

    final paddedS = box.south - latPad;
    final paddedN = box.north + latPad;
    final paddedW = box.west - lonPad;
    final paddedE = box.east + lonPad;

    // Enforce minimum radius as a degree half-extent. Uses the same
    // approximation (no cos(lat) correction) as the pre-Phase-3 code so
    // Regional values match v0.12 byte-for-byte.
    final minHalf = config.minRadiusKm / kmPerDegree;
    final midLat = (paddedS + paddedN) / 2;
    final midLon = (paddedW + paddedE) / 2;
    final effectiveS = min(paddedS, midLat - minHalf).clamp(-90.0, 90.0);
    final effectiveN = max(paddedN, midLat + minHalf).clamp(-90.0, 90.0);
    final effectiveW = min(paddedW, midLon - minHalf);
    final effectiveE = max(paddedE, midLon + minHalf);

    return 'a/${effectiveN.toStringAsFixed(2)}/${effectiveW.toStringAsFixed(2)}'
        '/${effectiveS.toStringAsFixed(2)}/${effectiveE.toStringAsFixed(2)}';
  }

  /// Validates a named-bulletin-group suffix. Spec §3.2.16 caps the addressee
  /// at 9 chars total (3 "BLN" + 1 slot + up to 5 name chars), so the suffix
  /// is 1–5 uppercase alphanumeric characters. Silently drop anything else —
  /// filter composition should never reject a malformed subscription outright.
  static bool _isValidNamedGroup(String s) =>
      RegExp(r'^[A-Z0-9]{1,5}$').hasMatch(s);
}
