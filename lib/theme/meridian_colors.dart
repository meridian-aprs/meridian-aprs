import 'package:flutter/material.dart';

/// Meridian APRS brand color constants.
///
/// These are the only hardcoded color values permitted in the codebase.
/// All structural / surface colors must come from [Theme.of(context).colorScheme].
///
/// - [primary] / [primaryDark] are seed inputs to each platform theme tier.
/// - [signal] / [warning] / [danger] carry APRS protocol meaning and must
///   remain stable — they must never shift with dynamic color.
class MeridianColors {
  MeridianColors._();

  // Brand seed — used as dynamic color fallback and desktop/iOS primary.
  static const Color primary = Color(0xFF2563EB); // Meridian Blue
  static const Color primaryDark = Color(0xFF1D4ED8);

  // Brand mark — for in-app icon rendering (splash, about). Not used as M3 seed.
  static const Color brandPurple = Color(0xFF4D1D8C);

  // Semantic — fixed by design, never replaced by dynamic color equivalents.
  static const Color signal = Color(
    0xFF10B981,
  ); // Connected / received / active
  static const Color warning = Color(
    0xFFF59E0B,
  ); // Degraded connection / stale data
  static const Color danger = Color(0xFFEF4444); // Error / TX active indicator
}
