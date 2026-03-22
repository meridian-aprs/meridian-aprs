# Architecture

## Overview

Meridian APRS is structured as a layered architecture. Each layer has a single responsibility and depends only on layers below it.

```
┌─────────────────────────────────────┐
│           UI Layer                  │  lib/ui/, lib/screens/
├─────────────────────────────────────┤
│         Service Layer               │  lib/services/
├─────────────────────────────────────┤
│         Packet Core                 │  lib/core/packet/, lib/core/ax25/
├─────────────────────────────────────┤
│        Transport Core               │  lib/core/transport/
├─────────────────────────────────────┤
│      Platform Channels              │  android/, ios/, linux/, macos/, windows/, web/
└─────────────────────────────────────┘
```

---

## Layer Responsibilities

### UI Layer (`lib/ui/`, `lib/screens/`)

Renders the application. Contains screens, widgets, and map integration. Observes state exposed by the Service Layer — it does not directly call transports or parsers. Uses Material 3. Target: modern, purpose-built ham radio tool aesthetics, not a utility app.

### Service Layer (`lib/services/`)

Orchestrates application logic. Manages connection lifecycle, routes incoming packets to the parser, maintains station state, and exposes streams/notifiers to the UI layer. Acts as the boundary between the platform-aware transport world and the pure-Dart packet world.

### Packet Core (`lib/core/packet/`, `lib/core/ax25/`)

Pure Dart. No platform imports, no FFI. Responsible for:
- AX.25 frame parsing (address fields, control, PID, information)
- APRS information field decoding (position, message, object, weather, telemetry, etc.)
- Encoding outgoing packets for transmit

**This layer must remain pure Dart** so it runs identically on all 6 platforms including web.

### Transport Core (`lib/core/transport/`)

Platform-aware. Responsible for moving bytes between the app and the outside world. Each transport implements a common abstract interface so the Service Layer is transport-agnostic.

Transports:
- **`AprsIsTransport`** — direct TCP socket connection to `rotate.aprs2.net:14580`
- **APRS-IS WebSocket** — WebSocket proxy for web platform (browser cannot open raw TCP)
- **`SerialKissTransport`** — KISS over USB serial via `flutter_libserialport`; desktop platforms only (Linux, macOS, Windows)
- **KISS/BLE** — via `flutter_blue_plus`; mobile platforms (iOS/Android); v0.4

### Platform Channels

Flutter's native integration layer. Used only where Flutter plugins do not cover a need. Minimize use — prefer community plugins.

---

## Platform Transport Matrix

| Transport | Linux | macOS | Windows | Android | iOS | Web |
|---|---|---|---|---|---|---|
| APRS-IS TCP | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| APRS-IS WebSocket proxy | — | — | — | — | — | ✅ |
| KISS/USB Serial | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| KISS/BLE | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ |

The web platform cannot open raw TCP sockets. Web users connect via a WebSocket-to-TCP proxy. This is a documented, acceptable limitation — see `docs/DECISIONS.md` ADR-004.

---

## Data Flow (Receive Path)

```
Transport (bytes) → KISS framing → AX.25 frame → APRS parser → Station model → UI
```

## Data Flow (Transmit Path)

```
UI action → Service Layer → APRS encoder → AX.25 frame → KISS framing → Transport (bytes)
```

### Packet log data flow (v0.2+)

```
AprsIsTransport (raw lines)
  → StationService.packetStream (broadcast stream)
      → StationService.recentPackets (500-packet rolling buffer)
      → PacketLogScreen (real-time list, type filter chips)
          → tap → showPacketDetailSheet → PacketDetailSheet
```

`PacketLogScreen` seeds its local list from `recentPackets` on entry so the log is not empty when navigating to the screen after packets have already arrived. All subsequent packets arrive via `packetStream`.

---

## AprsPacket Sealed Class Hierarchy (v0.2+)

All decoded APRS packets are represented as a sealed class hierarchy rooted at `AprsPacket` (`lib/core/packet/aprs_packet.dart`).

```
AprsPacket (sealed)
  ├── PositionPacket   DTI: ! = / @
  ├── WeatherPacket    DTI: _
  ├── MessagePacket    DTI: :
  ├── ObjectPacket     DTI: ;
  ├── ItemPacket       DTI: )
  ├── StatusPacket     DTI: >
  ├── MicEPacket       DTI: ` '
  └── UnknownPacket    catch-all for unrecognised or malformed input
```

`AprsParser.parse()` reads the data type identifier (DTI — the first character of the APRS info field) and dispatches to a type-specific private method. The parser never throws: any input that cannot be decoded yields an `UnknownPacket` with a `reason` string and the raw info field preserved for debugging.

The sealed hierarchy enables exhaustive `switch` dispatch at the UI layer without dynamic casting. Because the hierarchy is sealed, the Dart compiler enforces that every subtype is handled — omitting a case is a compile error.

`UnknownPacket` is load-bearing: it ensures the packet log always has something to display, and it makes it easy to identify packet types that need parser improvements.

---

## AprsSymbolWidget — Symbol Rendering Abstraction (v0.2+)

`AprsSymbolWidget` (`lib/ui/widgets/aprs_symbol_widget.dart`) is a stateless widget that renders an APRS symbol given a `symbolTable` and `symbolCode` character.

The v0.2 implementation maps symbol codes to Material Design icons (the same approach as the v0.1 `SymbolResolver`). The widget API is the call contract — all callers on the map and in the packet log use `AprsSymbolWidget` rather than resolving icon data directly.

At v1.0, the implementation inside `AprsSymbolWidget` will be swapped to render from a proper APRS bitmap atlas or SVG set. Because all call sites use the widget, the swap is a single-file change with no ripple across screens or other widgets.

`AprsSymbolWidget.iconDataForSymbol()` is also exposed as a static helper for callers (such as map marker builders) that need `IconData` directly rather than a widget subtree.

---

## Responsive Layout Strategy (UI Foundation)

The UI layer uses three scaffold variants selected at runtime by window width:

| Width | Scaffold | Layout |
|---|---|---|
| < 600 px | `MobileScaffold` | Full-screen map, FAB cluster (bottom-right), bottom sheets |
| 600–1024 px | `TabletScaffold` | Collapsed `NavigationRail` (72 px) + map + collapsed bottom panel |
| > 1024 px | `DesktopScaffold` | Extended `NavigationRail` (240 px) + map + 320 px side panel |

`ResponsiveLayout` (`lib/ui/layout/responsive_layout.dart`) reads `MediaQuery.of(context).size.width` and returns the appropriate scaffold. All three scaffolds receive the same props: `StationService`, `MapController`, `markers`, `tileUrl`, and a settings navigation callback.

`MeridianMap` (`lib/ui/layout/meridian_map.dart`) isolates all flutter_map configuration so the three scaffolds share a single map widget with a clean interface.

---

## Theme System — Three-Tier Platform Architecture

Meridian uses a three-tier platform theme architecture. Each tier can evolve independently while sharing a common brand identity. The Android tier is implemented; iOS and desktop stubs are in place for future PRs.

```
┌─────────────────────────────────────────────────────────┐
│                   Meridian ThemeController              │
│         (light/dark mode, seed color preference)        │
├─────────────────┬───────────────────┬───────────────────┤
│   Android Tier  │     iOS Tier      │   Desktop Tier    │
│  M3 Expressive  │  Cupertino (std)  │  M3 Static Brand  │
│  + Dynamic Color│  → Liquid Glass   │  Windows/macOS/   │
│  (Android 12+)  │    when Flutter   │  Linux            │
│  + Seed fallback│    supports it    │                   │
└─────────────────┴───────────────────┴───────────────────┘
```

### Brand Tokens (`lib/theme/meridian_colors.dart`)

All hardcoded color values live exclusively in `MeridianColors`. Surface and structural colors come from `Theme.of(context).colorScheme`.

| Token | Value | Usage |
|---|---|---|
| `primary` | `#2563EB` | Meridian Blue — seed input to theme tiers |
| `primaryDark` | `#1D4ED8` | Primary variant |
| `signal` | `#10B981` | Connected / received / active |
| `warning` | `#F59E0B` | Degraded connection / stale data |
| `danger` | `#EF4444` | Error / TX active indicator |

Semantic tokens (`signal`, `warning`, `danger`) carry APRS protocol meaning and must never shift with dynamic color.

### ThemeController (`lib/theme/theme_controller.dart`)

`ThemeController extends ChangeNotifier` manages two pieces of state: `themeMode` (`ThemeMode`, persisted as int under key `'theme_mode'`) and `seedColor` (`Color`, persisted as `toARGB32()` int under key `'seed_color'`). Provided at the app root via `provider`.

### App Root Platform Branching

`MeridianApp.build()` in `lib/main.dart` branches on platform before constructing the app widget:

```dart
if (!kIsWeb && Platform.isIOS) {
  // Returns CupertinoApp with buildIosTheme(brightness: resolvedBrightness)
}
// Android + Desktop: DynamicColorBuilder + MaterialApp with buildAndroidTheme()
```

`_resolveIosBrightness(ThemeMode)` maps `ThemeController.themeMode` to a `Brightness` for `CupertinoThemeData`. `ThemeMode.system` reads `WidgetsBinding.instance.platformDispatcher.platformBrightness`.

### Android Tier (`lib/theme/android_theme.dart`)

`buildAndroidTheme({ColorScheme? dynamicLight, ColorScheme? dynamicDark, required Color seedColor})` builds the light/dark `ThemeData` pair:

- On Android 12+: uses `DynamicColorBuilder` wallpaper-derived schemes (passed in from `MeridianApp.build()`).
- On Android < 12, desktop, iOS: falls back to `ColorScheme.fromSeed(seedColor: seedColor)`.
- Applies M3 Expressive tokens via `withM3ETheme()` from the `m3e_design` package (`M3ETheme` ThemeExtension covering colors, typography, shapes, spacing, motion).
- Applies M3 Expressive rounded shape ramp (sm=20px, md=28px) to `cardTheme`, `bottomSheetTheme`, `dialogTheme`, `floatingActionButtonTheme`.

`DynamicColorBuilder` wraps `MaterialApp` at the app root in `MeridianApp.build()`. It returns null schemes on platforms that don't support dynamic color — `buildAndroidTheme` handles this via the seed fallback.

The map tile URL is theme-aware: light mode uses OSM standard tiles; dark mode uses CartoDB dark tiles (subdomain rotation via `{s}`).

---

## TNC Transport (v0.3+)

### SerialKissTransport

Implements `AprsTransport` (the same interface as `AprsIsTransport`). Uses `flutter_libserialport` for serial I/O on desktop (Linux, macOS, Windows).

Internal pipeline:

```
serial bytes → KissFramer.addBytes → Ax25Parser.parseFrame → AprsParser.parseFrame
  → APRS-IS format line (SOURCE>DEST,PATH:INFO) → lines stream
```

Platform guard: conditional export (`dart.library.io`) with `UnsupportedError` stub for web/mobile. `StationService` is unchanged — it consumes the same `Stream<String> lines` it always has.

### KissFramer

Pure Dart KISS protocol framer (`lib/core/transport/kiss_framer.dart`). Stateful byte accumulator — feed raw serial bytes via `addBytes`, receive decoded AX.25 payloads on `frames` stream. Static `encode` wraps a payload for transmission. FEND/FESC/TFEND/TFESC constants follow the KISS TNC spec.

### Ax25Parser

Pure Dart AX.25 UI frame byte decoder (`lib/core/ax25/ax25_parser.dart`). Decodes the address block (destination, source, digipeaters), control byte, PID byte, and information field. Returns sealed `Ax25ParseResult` (`Ax25Ok` | `Ax25Err`). Never throws.

### TncPreset / TncConfig

- `TncPreset` (`lib/core/transport/tnc_preset.dart`): immutable preset for known TNC hardware (Mobilinkd TNC4 + Custom sentinel). `TncPreset.all` is the full list used by UI dropdowns and is easily extended for v0.4 BLE presets.
- `TncConfig` (`lib/core/transport/tnc_config.dart`): runtime serial + KISS configuration. `fromPreset` factory, `toPrefsMap`/`fromPrefsMap` for SharedPreferences persistence.

### TncService

`ChangeNotifier` service (`lib/services/tnc_service.dart`) that owns the `SerialKissTransport` lifecycle. Bridges decoded APRS lines into `StationService` via `StationService.ingestLine`. Persists `TncConfig` across restarts. Exposes `connectionState: Stream<ConnectionStatus>`, `currentStatus`, `lastErrorMessage`, and `availablePorts()`.

---

## Key Dependencies

| Package | Purpose |
|---|---|
| `flutter_map` | Map rendering with OpenStreetMap tiles |
| `flutter_blue_plus` | BLE transport (KISS/BLE) |
| `flutter_libserialport` | USB serial transport (KISS/USB) |
| `provider` | ThemeController ChangeNotifier wiring |
| `shared_preferences` | Theme mode, seed color, and onboarding flag persistence |
| `dynamic_color` | Android 12+ wallpaper-derived ColorScheme |
| `m3e_design` | M3 Expressive ThemeExtension (shapes, spacing, motion, typography tokens) |
| `flutter_m3shapes` | M3 Expressive shape widgets (M3Container) |

No third-party APRS or AX.25 libraries — parsing is implemented in-house in the Packet Core.
