// GENERATED FILE - do not edit by hand
// Regenerate from design tokens when palette changes.
//
// Meridian APRS brand palette
// Seed: #4D1D8C (Boosted purple)
// Derived tonal palettes + harmonized neutrals + fixed semantic colors.

import 'package:flutter/material.dart';

/// Meridian brand color tokens.
///
/// This is the single source of truth for all brand colors. Do NOT hardcode
/// hex values anywhere else in the app — reference these tokens.
///
/// Organization:
/// - [brandSeed] — the anchor color used for the app icon and marketing
/// - [brand] tonal palette — 13 tones for UI states and surfaces
/// - [neutral] / [neutralVariant] — warm-tinted grays for backgrounds
/// - [Semantic] colors — fixed APRS protocol meaning, never dynamic-colored
class MeridianColors {
  MeridianColors._();

  /// The anchor color. Used for the app icon, wordmark, and as the Material 3
  /// seed color for ColorScheme.fromSeed() on Android fallback and desktop.
  static const Color brandSeed = Color(0xFF4D1D8C);

  // --- Brand tonal palette (13 tones, 0..100) ---
  // Used for: primary UI roles, hover/pressed states, brand-tinted surfaces.
  static const Color brand000 = Color(0xFF000000);
  static const Color brand010 = Color(0xFF19141F);
  static const Color brand020 = Color(0xFF312145);
  static const Color brand030 = Color(0xFF472277);
  static const Color brand040 = Color(0xFF5D23A9);
  static const Color brand050 = Color(0xFF742CD3);
  static const Color brand060 = Color(0xFF9056DC);
  static const Color brand070 = Color(0xFFAC80E5);
  static const Color brand080 = Color(0xFFC8B0E8);
  static const Color brand090 = Color(0xFFE4DCEF);
  static const Color brand095 = Color(0xFFF2F0F5);
  static const Color brand099 = Color(0xFFFCFCFD);
  static const Color brand100 = Color(0xFFFFFFFF);

  // --- Neutral palette (warm-tinted gray, 13 tones) ---
  // Used for: backgrounds, surfaces, container levels, dividers.
  static const Color neutral000 = Color(0xFF000000);
  static const Color neutral010 = Color(0xFF19181B);
  static const Color neutral020 = Color(0xFF332F37);
  static const Color neutral030 = Color(0xFF4C4752);
  static const Color neutral040 = Color(0xFF655F6D);
  static const Color neutral050 = Color(0xFF7E7788);
  static const Color neutral060 = Color(0xFF9892A0);
  static const Color neutral070 = Color(0xFFB2ADB8);
  static const Color neutral080 = Color(0xFFCCC8D0);
  static const Color neutral090 = Color(0xFFE5E4E7);
  static const Color neutral095 = Color(0xFFF2F1F3);
  static const Color neutral099 = Color(0xFFFCFCFD);
  static const Color neutral100 = Color(0xFFFFFFFF);

  // --- Neutral variant palette (slightly more chromatic, 13 tones) ---
  // Used for: outlines, variant surfaces needing a bit more brand tint.
  static const Color neutralVariant000 = Color(0xFF000000);
  static const Color neutralVariant010 = Color(0xFF19161D);
  static const Color neutralVariant020 = Color(0xFF322C3A);
  static const Color neutralVariant030 = Color(0xFF4B4356);
  static const Color neutralVariant040 = Color(0xFF645973);
  static const Color neutralVariant050 = Color(0xFF7D6F90);
  static const Color neutralVariant060 = Color(0xFF978CA6);
  static const Color neutralVariant070 = Color(0xFFB1A9BC);
  static const Color neutralVariant080 = Color(0xFFCBC5D3);
  static const Color neutralVariant090 = Color(0xFFE5E2E9);
  static const Color neutralVariant095 = Color(0xFFF2F1F4);
  static const Color neutralVariant099 = Color(0xFFFCFCFD);
  static const Color neutralVariant100 = Color(0xFFFFFFFF);

  // --- Semantic colors (FIXED — APRS protocol meaning) ---
  //
  // These colors carry meaning tied to APRS state. They do NOT shift with
  // Material You dynamic color and must not be altered per-theme.
  //
  // - [signal]  : connected, received packet, active transport
  // - [warning] : degraded, stale, reconnecting
  // - [danger]  : error, TX active (attention required)
  // - [info]    : informational (non-critical guidance)
  static const Color signal = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  /// Build a Material 3 ColorScheme for the LIGHT theme from the Meridian palette.
  ///
  /// Use this on desktop (no dynamic color available) or as the Android fallback
  /// when the user hasn't picked a custom seed and the OS doesn't expose wallpaper
  /// colors (pre-Android 12).
  static ColorScheme lightColorScheme() {
    return ColorScheme.fromSeed(
      seedColor: brandSeed,
      brightness: Brightness.light,
    );
  }

  /// Build a Material 3 ColorScheme for the DARK theme from the Meridian palette.
  static ColorScheme darkColorScheme() {
    return ColorScheme.fromSeed(
      seedColor: brandSeed,
      brightness: Brightness.dark,
    );
  }
}
