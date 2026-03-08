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
- **APRS-IS TCP** — direct TCP socket connection to `rotate.aprs2.net:14580`
- **APRS-IS WebSocket** — WebSocket proxy for web platform (browser cannot open raw TCP)
- **KISS/USB Serial** — via `flutter_libserialport`; desktop platforms only
- **KISS/BLE** — via `flutter_blue_plus`; mobile platforms (iOS/Android)

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

## Theme Token System (UI Foundation)

All colors are defined as static constants on `AppColors` in `lib/ui/theme/app_theme.dart`:

| Token | Light | Dark |
|---|---|---|
| Primary | `#2563EB` | `#3B82F6` |
| Primary variant | `#1D4ED8` | `#2563EB` |
| Accent (connected) | `#10B981` | `#10B981` |
| Warning (connecting) | `#F59E0B` | `#F59E0B` |
| Danger (error/TX) | `#EF4444` | `#EF4444` |
| Surface | `#FFFFFF` | `#0F172A` |
| Surface variant | `#F8FAFC` | `#1E293B` |
| Text | `#0F172A` | `#F1F5F9` |

`AppTheme.lightTheme` and `AppTheme.darkTheme` build `ThemeData` from these tokens using `ColorScheme.fromSeed`. No widget may hard-code a color — all values must come from `Theme.of(context)` or `AppColors`.

`ThemeProvider` (`lib/ui/theme/theme_provider.dart`) extends `ChangeNotifier` and persists the user's `ThemeMode` choice to `SharedPreferences` under key `'theme_mode'`. Default is `ThemeMode.system`. It is provided at the top of the widget tree via `provider`.

The map tile URL is theme-aware: light mode uses OSM standard tiles; dark mode uses CartoDB dark tiles (subdomain rotation via `{s}`).

---

## Key Dependencies

| Package | Purpose |
|---|---|
| `flutter_map` | Map rendering with OpenStreetMap tiles |
| `flutter_blue_plus` | BLE transport (KISS/BLE) |
| `flutter_libserialport` | USB serial transport (KISS/USB) |
| `provider` | ThemeProvider ChangeNotifier wiring |
| `shared_preferences` | Theme mode and onboarding flag persistence |

No third-party APRS or AX.25 libraries — parsing is implemented in-house in the Packet Core.
