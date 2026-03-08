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

## Key Dependencies

| Package | Purpose |
|---|---|
| `flutter_map` | Map rendering with OpenStreetMap tiles |
| `flutter_blue_plus` | BLE transport (KISS/BLE) |
| `flutter_libserialport` | USB serial transport (KISS/USB) |

No third-party APRS or AX.25 libraries — parsing is implemented in-house in the Packet Core.
