# Meridian APRS — Platform Theme Strategy

**Status:** Adopted post-UI-Foundation  
**Supersedes:** Theme System section (§2) of `docs/UI_UX_SPEC.md`  
**Related:** `docs/ARCHITECTURE.md`, `docs/DECISIONS.md`

---

## Overview

Meridian uses a **three-tier platform theme architecture**. Each platform tier has a distinct theming strategy that respects native platform conventions while sharing a common Meridian brand identity. The tiers are isolated so that each can evolve independently — in particular, the iOS tier is designed for a clean upgrade path to Apple's Liquid Glass design language once Flutter's Cupertino library officially supports iOS 26+.

```
┌─────────────────────────────────────────────────────────┐
│                   Meridian ThemeController              │
│         (light/dark mode, seed color preference)        │
├─────────────────┬───────────────────┬───────────────────┤
│   Android Tier  │     iOS Tier      │   Desktop Tier    │
│                 │                   │                   │
│  M3 Expressive  │  Cupertino (std)  │  M3 Static Brand  │
│  + Dynamic Color│  → Liquid Glass   │  Windows/macOS/   │
│  (Android 12+)  │    when Flutter   │  Linux            │
│  + Seed fallback│    supports it    │                   │
└─────────────────┴───────────────────┴───────────────────┘
```

---

## Tier 1: Android — Material 3 Expressive + Dynamic Color

### Behavior

- On **Android 12+**: Uses `DynamicColorBuilder` to read the system-generated `ColorScheme` derived from the user's wallpaper (Material You). The app color palette adapts fully to the user's device personality.
- On **Android < 12**: Falls back to a `ColorScheme.fromSeed()` built from the user's chosen seed color (see Seed Color Setting below). Defaults to Meridian Purple (`#4D1D8C`) on first launch.
- Both light and dark dynamic schemes are provided; the active one is selected by the current `ThemeMode`.

### M3 Expressive Layer

- `m3e_design` package provides the M3 Expressive `ThemeExtension` — covering expressive shape tokens, spacing ramps, motion durations/easings, and typography variants.
- Applied via `.toM3EThemeData()` on the resolved `ColorScheme`, whether dynamic or seed-based.
- Expressive shapes (`flutter_m3shapes`) applied to cards, bottom sheets, FABs, and dialogs.

### Packages

| Package | Purpose |
|---|---|
| `dynamic_color` | Reads Android 12+ wallpaper-derived ColorScheme |
| `m3e_design` | M3 Expressive tokens (ThemeExtension) |
| `flutter_m3shapes` | M3 Expressive shape library |

### Seed Color Setting (Fallback + User Preference)

- Exposed in **Settings → Appearance → App Color** on Android only.
- A color picker (or curated palette of 8–10 harmonious options) lets users set their preferred seed color.
- Used as fallback on pre-Android-12 devices.
- On Android 12+, this setting is visible but labeled "Used on older Android versions" — dynamic color takes precedence.
- Persisted to local preferences storage.

---

## Tier 2: iOS — Standard Cupertino (Liquid Glass Ready)

### Current Behavior (iOS < 26 / Flutter today)

- Uses Flutter's `CupertinoApp` with `CupertinoThemeData`.
- Light and dark Cupertino themes defined separately.
- Navigation uses `CupertinoNavigationBar` and `CupertinoPageRoute` transitions.
- System chrome (tab bars, navigation bars, action sheets, alerts) uses standard Cupertino widgets throughout.
- Typography uses San Francisco (system font) automatically via Cupertino defaults.
- Color accents use Meridian Purple mapped to `CupertinoThemeData.primaryColor`.

### Liquid Glass Upgrade Path

The iOS theme layer is deliberately isolated in a single theme configuration file (`lib/theme/ios_theme.dart`). When Flutter's Cupertino library adds official Liquid Glass / iOS 26 support, the upgrade is:

1. Update `ios_theme.dart` to use the new Cupertino styling APIs.
2. Add version-gating if graceful fallback to pre-iOS-26 styling is needed.
3. No changes required to any screen, widget, or navigation code.

This is a **contained swap, not a rearchitecture**.

### What Does NOT Change for iOS

- Navigation structure and routing
- Screen content and layout logic  
- Custom Meridian widgets (map, packet log, station tiles, etc.)
- Settings screens and data model
- All non-chrome UI

### No Dynamic Color on iOS

iOS does not expose a system-level dynamic color API comparable to Android's Material You. The Cupertino theme uses fixed Meridian brand colors (Meridian Purple as primary). This is consistent with how native iOS apps behave.

---

## Tier 3: Desktop — Material 3 Static Brand Theme

### Platforms

Windows, macOS, Linux.

### Behavior

- Uses `MaterialApp` with `ThemeData` (`useMaterial3: true`).
- `ColorScheme.fromSeed(seedColor: MeridianColors.brandSeed)` — fixed Meridian Purple seed, no dynamic color.
- No per-OS customization (no macOS-native chrome, no Windows Fluent). A consistent, modern Meridian-branded Material 3 experience across all desktop platforms.
- Full M3 component set (NavigationRail, Cards, Dialogs, etc.) but without M3 Expressive shape/motion extensions (those are Android-only for now).

### Dark Mode

- Default: follows `MediaQuery.platformBrightness` (OS system preference).
- User override: **Settings → Appearance → Theme** offers Light / Dark / System options.
- Preference persisted to local storage.
- The same override toggle is present on Android and iOS for consistency, but on those platforms it also affects the dynamic color light/dark scheme selection.

---

## Shared: ThemeController

A single `ThemeController` (Riverpod provider or equivalent) manages:

| Property | Description |
|---|---|
| `themeMode` | `ThemeMode.light`, `.dark`, or `.system` (default: `.system`) |
| `seedColor` | `Color` — Meridian Purple default, user-configurable on Android |
| `resolvedColorScheme` | The active `ColorScheme` after dynamic color / seed resolution |

`ThemeController` is the single source of truth. Widgets never read platform or brightness directly — they always go through the controller or `Theme.of(context)`.

---

## Shared: Meridian Brand Tokens

These are constants that exist regardless of platform tier. They represent the Meridian brand identity and are used as inputs to each tier's theme generation, not as hardcoded colors in widgets.

```dart
// lib/theme/meridian_colors.dart  (GENERATED — do not edit by hand)

class MeridianColors {
  // Brand anchor — app icon, wordmark, M3 seed on desktop + Android fallback
  static const Color brandSeed = Color(0xFF4D1D8C); // Meridian Purple

  // Brand tonal palette (13 tones, 0..100)
  static const Color brand000 = Color(0xFF000000);
  // … brand010 – brand100 (see file for full list)

  // Neutral palettes (warm-tinted grays, 13 tones each)
  // neutral000..neutral100, neutralVariant000..neutralVariant100

  // Semantic — APRS protocol meaning, fixed across all themes
  static const Color signal  = Color(0xFF10B981); // Connected / received / active
  static const Color warning = Color(0xFFF59E0B); // Degraded / stale
  static const Color danger  = Color(0xFFEF4444); // Error / TX active
  static const Color info    = Color(0xFF3B82F6); // Informational guidance
}
```

Semantic colors (`signal`, `warning`, `danger`, `info`) are used in custom Meridian widgets like `MeridianStatusPill` and beacon state indicators. They are fixed by design — they carry meaning tied to APRS protocol state and must not shift with dynamic color.

---

## Platform Detection

Theme tier selection is gated at the `MaterialApp` / `CupertinoApp` level using `Platform.isIOS`. This is the only place platform-gating occurs in the theme system. Everything below the app root receives the correct theme via `Theme.of(context)` or `CupertinoTheme.of(context)` without needing to know the platform.

```dart
// Pseudocode — lib/app.dart

Widget build(BuildContext context) {
  if (Platform.isIOS) {
    return CupertinoApp(/* iOS tier */);
  }
  return DynamicColorBuilder(
    builder: (lightDynamic, darkDynamic) {
      // Android: use dynamic color or seed fallback
      // Desktop: use seed color (DynamicColorBuilder returns null on desktop)
      return MaterialApp(/* Android / Desktop tier */);
    },
  );
}
```

---

## Settings → Appearance

| Setting | Platforms | Options |
|---|---|---|
| Theme mode | All | System (default) / Light / Dark |
| App color (seed) | Android | Color picker / curated palette — used as fallback on Android < 12 |

The App Color setting is hidden on iOS and desktop — it has no effect there and showing it would be confusing.

---

## Future Considerations

- **iOS Liquid Glass:** When Flutter officially supports iOS 26+ Liquid Glass in the Cupertino library, update `lib/theme/ios_theme.dart` only. No other changes needed.
- **macOS native chrome:** If demand warrants it, macOS could later adopt a more native look using `macos_ui` or similar. The desktop tier is currently unified across all three desktop platforms for simplicity.
- **Dynamic color on desktop:** Windows 11 exposes accent colors via the OS. This could be explored post-v1.0 using a platform channel if desired.