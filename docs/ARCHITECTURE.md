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

Meridian uses a three-tier platform theme architecture. Each tier can evolve independently while sharing a common brand identity. All three tiers are fully implemented.

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
if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
  // Returns MaterialApp with buildDesktopTheme(seedColor: MeridianColors.primary)
  // No DynamicColorBuilder — desktop platforms do not support wallpaper color extraction
}
// Android: DynamicColorBuilder + MaterialApp with buildAndroidTheme()
```

`_resolveIosBrightness(ThemeMode)` maps `ThemeController.themeMode` to a `Brightness` for `CupertinoThemeData`. `ThemeMode.system` reads `WidgetsBinding.instance.platformDispatcher.platformBrightness`.

### Desktop Tier (`lib/theme/desktop_theme.dart`)

`buildDesktopTheme({required Color seedColor})` builds the light/dark `ThemeData` pair for Windows, macOS, and Linux:

- Material 3 (`useMaterial3: true`) with `ColorScheme.fromSeed(seedColor: seedColor)`.
- Fixed seed: callers always pass `MeridianColors.primary` — no user-configurable color picker on desktop.
- No `DynamicColorBuilder` wrapper, no M3 Expressive `ThemeExtension`.
- `themeMode` from `ThemeController` is respected for light/dark/system switching, identical to the Android branch.

### Android Tier (`lib/theme/android_theme.dart`)

`buildAndroidTheme({ColorScheme? dynamicLight, ColorScheme? dynamicDark, required Color seedColor})` builds the light/dark `ThemeData` pair:

- On Android 12+: uses `DynamicColorBuilder` wallpaper-derived schemes (passed in from `MeridianApp.build()`).
- On Android < 12, desktop, iOS: falls back to `ColorScheme.fromSeed(seedColor: seedColor)`.
- Applies M3 Expressive tokens via `withM3ETheme()` from the `m3e_design` package (`M3ETheme` ThemeExtension covering colors, typography, shapes, spacing, motion).
- Applies M3 Expressive rounded shape ramp (sm=20px, md=28px) to `cardTheme`, `bottomSheetTheme`, `dialogTheme`, `floatingActionButtonTheme`.

`DynamicColorBuilder` wraps `MaterialApp` at the app root in `MeridianApp.build()`. It returns null schemes on platforms that don't support dynamic color — `buildAndroidTheme` handles this via the seed fallback.

The map tile URL is theme-aware: light mode uses OSM standard tiles; dark mode uses CartoDB dark tiles (subdomain rotation via `{s}`).

### Brand Assets

- **Source of truth**: `assets/icons/meridian-icon-master.svg` — single compound path, `evenodd` fill-rule, 512×512 viewBox.
- **Brand color token**: `MeridianColors.brandPurple` = `#4D1D8C`. For in-app mark rendering (splash, about screen) only — not used as the M3 theme seed.
- **Regenerating launcher icons**: `dart run flutter_launcher_icons` — reads PNG masters from `assets/icons/generated/`.
- **Regenerating PNG masters** (if SVG source changes):
  ```bash
  magick -density 300 -background white assets/icons/meridian-icon-master.svg -flatten -resize 1024x1024 assets/icons/generated/icon-1024.png
  magick -density 300 -background transparent assets/icons/meridian-icon-adaptive-fg.svg -resize 432x432 assets/icons/generated/icon-adaptive-fg-432.png
  magick -density 300 -background none assets/icons/meridian-icon-adaptive-bg.svg -resize 432x432 assets/icons/generated/icon-adaptive-bg-432.png
  ```
- **Linux**: icon bundled as `linux/meridian.png`; `.desktop` system integration deferred to v1.0 packaging.

---

## TNC Transport (v0.3+, extended in v0.4)

### `KissTncTransport` Interface

`KissTncTransport` (`lib/core/transport/kiss_tnc_transport.dart`) is the abstract interface for all hardware TNC transports. It operates at the raw byte level:

```dart
abstract interface class KissTncTransport {
  Stream<Uint8List> get frameStream;        // raw AX.25 bytes (KISS header stripped)
  Stream<ConnectionStatus> get connectionState;
  ConnectionStatus get currentStatus;
  bool get isConnected;
  Future<void> connect();
  Future<void> disconnect();
  Future<void> sendFrame(Uint8List ax25Frame);
}
```

Both `SerialKissTransport` (USB serial, desktop) and `BleTncTransport` (BLE, mobile) implement this interface. APRS parsing is **not** part of this interface — it is the service layer's responsibility.

### `TransportManager`

`TransportManager` (`lib/core/transport/transport_manager.dart`) is a `ChangeNotifier` that holds the currently active `KissTncTransport` and bridges its `frameStream` and `connectionState` to caller-facing broadcast streams. It provides `connectSerial(TncConfig)`, `connectBle(BluetoothDevice)`, and `disconnect()`. The `activeType` getter (`TransportType.none | .serial | .ble`) lets the UI show the correct label on the TNC status pill.

### `SerialKissTransport`

Implements `KissTncTransport`. Uses `flutter_libserialport` for serial I/O on desktop (Linux, macOS, Windows).

Internal pipeline:

```
serial bytes → KissFramer.addBytes → AX.25 frame bytes → frameStream
```

Platform guard: conditional export (`dart.library.io`) with `UnsupportedError` stub for web/mobile.

### `BleTncTransport` (v0.4)

Implements `KissTncTransport`. Uses `flutter_blue_plus` for BLE I/O on iOS and Android. Targets Mobilinkd-compatible devices via Mobilinkd's UART-over-BLE GATT service (UUIDs in `lib/core/transport/ble_constants.dart`).

Connection flow: `connect()` → negotiate MTU 512 → discover services → find TX/RX characteristics → subscribe to TX notifications → ready.

Internal pipeline:

```
BLE notify chunks → KissFramer.addBytes → AX.25 frame bytes → frameStream
```

Outgoing frames: `KissFramer.encode(ax25Frame)` → split into MTU-sized chunks → `rxChar.write(chunk, withoutResponse: false)`.

Platform guard: conditional export (`dart.library.io`) with `UnsupportedError` stub for web.

### KissFramer

Pure Dart KISS protocol framer (`lib/core/transport/kiss_framer.dart`). Stateful byte accumulator — feed raw bytes via `addBytes`, receive decoded AX.25 payloads on `frames` stream. Static `encode` wraps a payload for transmission. FEND/FESC/TFEND/TFESC constants follow the KISS TNC spec. Shared by both serial and BLE transports.

### Ax25Parser

Pure Dart AX.25 UI frame byte decoder (`lib/core/ax25/ax25_parser.dart`). Decodes the address block (destination, source, digipeaters), control byte, PID byte, and information field. Returns sealed `Ax25ParseResult` (`Ax25Ok` | `Ax25Err`). Never throws.

### TncPreset / TncConfig

- `TncPreset` (`lib/core/transport/tnc_preset.dart`): immutable preset for known TNC hardware (Mobilinkd TNC4 + Custom sentinel). `TncPreset.all` is the registry used by UI dropdowns.
- `TncConfig` (`lib/core/transport/tnc_config.dart`): runtime serial + KISS configuration. `fromPreset` factory, `toPrefsMap`/`fromPrefsMap` for SharedPreferences persistence.

### TncService

`ChangeNotifier` service (`lib/services/tnc_service.dart`) that owns a `TransportManager` internally. On each raw AX.25 frame from `TransportManager.frameStream`, it calls `AprsParser.parseFrame(frameBytes)` and feeds the resulting APRS line to `StationService.ingestLine`. Exposes `connectBle(BluetoothDevice)` for the BLE scanner UI. Persists `TncConfig` across restarts. Exposes `connectionState`, `currentStatus`, `lastErrorMessage`, `availablePorts()`, and `activeTransportType`.

---

## Beaconing Engine (v0.5)

### AprsEncoder

Pure Dart encoder (`lib/core/packet/aprs_encoder.dart`). Produces APRS-IS formatted strings from structured data. No platform imports.

- `encodePosition(...)` — uncompressed position packet (`DDmm.hhN/DDDmm.hhW`); DTI `!` (no messaging) or `=` (with messaging capability)
- `encodeMessage(...)` — APRS §14 message packet; addressee padded to 9 characters; `{id}` suffix when message ID provided
- `encodeAck(...)` / `encodeRej(...)` — ACK and REJ response packets
- Destination is `APZMDN` throughout. `TODO(tocall): register with WB4APR before v1.0`

### Ax25Encoder

Pure Dart AX.25 UI frame encoder (`lib/core/ax25/ax25_encoder.dart`). Complements `Ax25Parser`.

- `buildAprsFrame(...)` — constructs an `Ax25Frame` from source callsign + SSID + APRS info field + optional digipeater alias list (default: WIDE1-1, WIDE2-1)
- `encodeUiFrame(Ax25Frame)` — serialises to raw AX.25 bytes: each address is 7 bytes (6-byte left-shifted ASCII callsign + SSID byte), end-of-address-list bit set on the last address, control=0x03 (UI), PID=0xF0 (no layer 3)

### SmartBeaconing

Pure Dart algorithm implementation (`lib/core/beaconing/smart_beaconing.dart`). Stateless utility class — fully unit-testable with no platform dependencies.

- `SmartBeaconingParams` — configuration value object with `const defaults` (APRSdroid-compatible values: fastSpeed=100 km/h, fastRate=180 s, slowSpeed=5 km/h, slowRate=1800 s, minTurnTime=15 s, minTurnAngle=28°, turnSlope=255). Serialises via `toMap`/`fromMap`.
- `SmartBeaconing.computeInterval(p, speedKmh)` — linear interpolation between slowRate and fastRate
- `SmartBeaconing.turnThreshold(p, speedKmh)` — `turnSlope/speed + minAngle`, capped at 180°
- `SmartBeaconing.shouldTriggerTurn(p, speed, headingChange, timeSinceLast)` — true when `|headingChange| >= threshold` and cooldown elapsed

### BeaconingService

`ChangeNotifier` service (`lib/services/beaconing_service.dart`). Owns GPS subscription, beacon timer, and TX dispatch.

- Modes: `BeaconMode.manual` (on-demand), `BeaconMode.auto` (fixed interval), `BeaconMode.smart` (SmartBeaconing™ algorithm)
- `beaconNow()` — requests current GPS position (`Geolocator.getCurrentPosition`), encodes position via `AprsEncoder.encodePosition`, sends via `TxService.sendLine`
- Auto mode: `Timer.periodic` with `autoIntervalS` (default 600 s, persisted as `beacon_interval_s`)
- Smart mode: `Geolocator.getPositionStream` subscription; fires `beaconNow()` on interval OR turn trigger
- Exposes `lastBeaconAt` (DateTime) for FAB display
- Persists mode and smart params to SharedPreferences

### TxService

Global TX transport router (`lib/services/tx_service.dart`). `ChangeNotifier`. Routes all outgoing packets to either APRS-IS or TNC — a single global preference (not per-station); see ADR-023.

- `TxTransportPref { auto, aprsIs, tnc }` — stored in SharedPreferences (`tx_transport_pref`); `auto` resolves to TNC when connected, APRS-IS otherwise
- `sendLine(String aprsLine)` — routes to `AprsTransport.sendLine` (APRS-IS) or builds AX.25 bytes via `Ax25Encoder` and calls `KissTncTransport.sendFrame` (TNC)
- `TxEvent` sealed class — `TxEventTncDisconnected` / `TxEventTncReconnected` drive UI banners without persisting fallback

---

## Messaging Architecture (v0.5)

### MessageService

`ChangeNotifier` service (`lib/services/message_service.dart`). Owns conversation state, retry scheduler, and ACK handling.

- `Conversation` — holds peer callsign, message list, unread count, last activity timestamp; sorted newest-first
- `MessageEntry` — localId (UUID), wireId (APRS message ID), text, timestamp, direction, `MessageStatus`
- `MessageStatus { pending, acked, retrying, failed, rejected }` — drives per-bubble status icons in the thread UI

Retry scheduler (per pending outbound message):
- Backoff delays: 30 / 60 / 120 / 240 / 480 seconds (APRS spec §14 guidance); see ADR-022
- One `Timer` per pending message; cancelled on ACK receipt
- After 5th retry without ACK: status → `failed`

Inbound handling:
- Subscribes to `StationService.packetStream`, filters `MessagePacket` addressed to `_settings.fullAddress`
- ACK/REJ lines routed to the appropriate pending message
- Duplicate detection via `Set<String>` keyed `"sourceCallsign:wireId"` — same pair is ignored

Message ID counter:
- SharedPreferences key `message_id_counter` (int); incremented per send; wraps 999 → 001
- Formatted as zero-padded 3-digit string

---

## Android Background Service (v0.7)

### Overview

An Android foreground service keeps transport connections alive when Meridian is backgrounded. This prevents the OS from killing the app process and allows beaconing to continue.

**Key design decision:** The `flutter_foreground_task` `TaskHandler` runs in a background isolate and cannot access Provider-hosted services. The service is therefore a "process keepalive only" — all transport and beaconing logic continues to run in the main Dart isolate via the existing service layer.

### MeridianConnectionTask (`lib/services/meridian_connection_task.dart`)

Minimal `TaskHandler` running in the background isolate. Contains no application logic. Its `onRepeatEvent` fires every 60 seconds as a heartbeat to prevent aggressive OEM firmware (MIUI, OneUI) from terminating idle services.

Entry point: `startMeridianConnectionTask()` (top-level function, `@pragma('vm:entry-point')`).

### BackgroundServiceManager (`lib/services/background_service_manager.dart`)

`ChangeNotifier` on the main isolate. The sole bridge between the Android foreground service lifecycle and the application state.

Responsibilities:
- Listens to `TncService`, `StationService`, and `BeaconingService` via `addListener`
- Calls `FlutterForegroundTask.startService()` / `stopService()` based on user action
- Calls `FlutterForegroundTask.updateService()` (debounced 500 ms) to push notification content
- Exposes `BackgroundServiceState` for reactive UI (connection screen, nav icon badge)
- Handles `ACCESS_BACKGROUND_LOCATION` permission check with `AlertDialog` rationale before starting

`BackgroundServiceState` values:

| State | Meaning |
|---|---|
| `stopped` | Service not running. Normal foreground-app operation. |
| `starting` | Permission check or service startup in progress. |
| `running` | Foreground service active; transports kept alive. |
| `reconnecting` | Service running but a transport is reconnecting. |
| `error` | Startup failed (permission denied, API error). |

### Notification Content

The persistent notification shows two lines:

- **Title** — connection summary ("Meridian — TNC + APRS-IS", "Meridian — Reconnecting…", etc.)
- **Body** — beaconing status ("Auto beacon every 5m", "SmartBeaconing™ active", "Beaconing off") with last beacon time appended when active

### Platform Matrix

| Feature | Linux | macOS | Windows | Android | iOS | Web |
|---|---|---|---|---|---|---|
| Background keepalive | ❌ | ❌ | ❌ | ✅ v0.7 | ✅ v0.9 | ❌ |

### Android Manifest Requirements

New permissions (v0.7): `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC` (API 34+), `FOREGROUND_SERVICE_CONNECTED_DEVICE` (API 34+), `ACCESS_BACKGROUND_LOCATION`, `POST_NOTIFICATIONS` (API 33+), `RECEIVE_BOOT_COMPLETED`.

Service element: `com.pravera.flutter_foreground_task.service.ForegroundService` with `foregroundServiceType="dataSync|connectedDevice"` and `stopWithTask="false"`.

---

## iOS Background Service (v0.9)

### Overview

iOS keeps the Meridian process alive via declared `UIBackgroundModes` rather than a foreground service. No separate background isolate is needed. The main Dart isolate continues to run, and `ConnectionRegistry`, `BeaconingService`, and `TxService` remain active while the app is backgrounded.

**UIBackgroundModes declared (`ios/Runner/Info.plist`):**

| Mode | Purpose |
|---|---|
| `voip` | Keeps APRS-IS TCP socket alive; iOS treats the process as hosting a real-time communication stream |
| `bluetooth-central` | Keeps BLE TNC connection alive; app continues receiving BLE packets while backgrounded |
| `location` | Delivers background GPS updates; required for SmartBeaconing heading/speed calculations |
| `fetch` | Background fetch opportunities (supplemental) |

**Background location permission:** "Always" (`NSLocationAlwaysAndWhenInUseUsageDescription`) is requested when the user switches to Auto or Smart beaconing mode. The `IosBackgroundService._requestBackgroundLocationIfNeeded()` checks the current permission level and signals the UI (via `needsBackgroundLocationPrompt`) to show a `CupertinoAlertDialog` directing the user to Settings.

### IosBackgroundService (`lib/services/ios_background_service.dart`)

Lightweight `ChangeNotifier` on the main isolate. Analogous to `BackgroundServiceManager` on Android, but simpler.

Responsibilities:
- Initializes `LiveActivities` with the App Group ID on startup
- Listens to `ConnectionRegistry` changes via `addListener` in `main.dart`; starts or ends the Live Activity accordingly
- Listens to `BeaconingService` changes; updates the Live Activity content and triggers background location permission check
- Exposes `needsBackgroundLocationPrompt` flag consumed by `_IosBackgroundLocationPrompt` in settings

`BackgroundServiceState` values: `stopped`, `running`, `error` (same enum shape as Android).

### Live Activity (`ios/MeridianLiveActivity/`)

SwiftUI widget extension (bundle ID: `com.meridianaprs.meridianAprs.MeridianLiveActivity`). Minimum deployment target: iOS 16.1 (gracefully absent on iOS 13.0–16.0 — background functionality is unaffected).

**Data flow:**
```
Dart (IosBackgroundService)
  └─ live_activities plugin (Map<String, dynamic> via App Group file share)
       └─ ActivityKit (iOS)
            ├─ Lock Screen banner (MeridianLockScreenView)
            └─ Dynamic Island (compact leading/trailing + expanded)
```

**Live Activity content (`LiveActivityContent`):**
- `connectedTransports: [String]` — display names of connected transports (e.g., `["APRS-IS", "BLE TNC"]`)
- `lastBeaconTimestamp: Date?` — timestamp of last successful beacon (shown as relative "3m ago")
- `beaconingActive: bool` — whether periodic beaconing is running
- `serviceStateLabel: String` — "Connected" or "Disconnected"

**App Group prerequisite:** `group.com.meridianaprs.meridianAprs` must be created in the Apple Developer portal and enabled on both targets. This is required for the `live_activities` plugin to share data between the Runner and the widget extension.

### iOS Info.plist Requirements (v0.9)

New keys added:
- `NSSupportsLiveActivities: true` — enables Live Activity API access
- `NSLocationAlwaysAndWhenInUseUsageDescription` — "Always" location permission rationale
- `NSLocationAlwaysUsageDescription` — legacy key for iOS < 11 (belt-and-suspenders)

The `NSLocationWhenInUseUsageDescription` and Bluetooth usage description keys already existed from v0.5/v0.4.

---

## Notification System (v0.11)

### Overview

v0.11 adds a full notification layer for incoming APRS messages. Delivery happens on the **main Dart isolate** on both platforms — there is no cross-isolate dispatch path needed because both Android (via `flutter_foreground_task` foreground service) and iOS (via VoIP `UIBackgroundMode`) keep the main isolate alive while backgrounded. See ADR-035.

### Channel Taxonomy

Four notification channels are registered at startup and serve as an extensible taxonomy for future alert types:

| Channel ID | Label | Default | Purpose |
|---|---|---|---|
| `messages` | Messages | Sound + vibration | Inbound APRS messages addressed to user |
| `alerts` | Alerts | Sound + vibration | WX/NWS alerts (reserved for future milestone) |
| `nearby` | Nearby | Vibration only | Nearby station activity (reserved) |
| `system` | System | Silent | Connection and TNC status (reserved) |

### `NotificationService` (`lib/services/notification_service.dart`)

`ChangeNotifier` service initialized in `main.dart` before `runApp`. Sits between `MessageService` and all platform delivery paths.

Responsibilities:
- Subscribes to `MessageService` via `addListener`; detects new inbound messages by comparing current vs. previous unread counts per callsign
- Checks `NotificationPreferences` (channel enabled, sound, vibration) before dispatching
- Dispatches system notifications via `flutter_local_notifications` on Android/iOS/macOS
- Dispatches desktop toasts via `local_notifier` on Windows/Linux (tap-to-navigate, no inline reply)
- Triggers `InAppBannerController` unless the user is already in that conversation's thread
- Handles inline reply action payloads from Android `RemoteInput` and iOS `UNTextInputAction`; routes reply text to `MessageService.sendMessage()`
- Handles cold-start navigation via `getNotificationAppLaunchDetails()` (post-frame callback)
- Drains a SharedPreferences reply outbox on startup for terminated-app inline replies

**Android:** `BigTextStyleInformation` for single messages; `InboxStyleInformation` grouped summary when 3+ conversations have unread messages. `RemoteInput` inline reply action on the `messages` channel.

**iOS:** `DarwinNotificationCategory('messages')` with `DarwinNotificationAction.text` for inline reply. Notifications present in foreground via `presentAlert: true` (handled automatically by `flutter_local_notifications` — no custom `AppDelegate` code needed).

**Background inline reply (terminated app):** The `@pragma('vm:entry-point')` top-level handler `onNotificationBackgroundResponse` writes replies to a SharedPreferences outbox (`notification_reply_outbox`). `NotificationService._drainReplyOutbox()` processes the queue on the next main-isolate startup.

**Navigation from notification tap:** A `GlobalKey<NavigatorState> navigatorKey` is declared in `lib/main.dart` and passed to all three `MaterialApp`/`CupertinoApp` instances. `NotificationService` holds a reference and calls `navigatorKey.currentState?.push(buildPlatformRoute(...))`.

### `InAppBannerOverlay` (`lib/ui/widgets/in_app_banner_overlay.dart`)

In-app slide-in notification banner. Wraps the home widget in `MeridianApp.build()` so it appears on every screen.

- **Mobile:** Full-width, anchored top, slides in from above using `SlideTransition`
- **Desktop (>1024 px):** Fixed-width (320 px), anchored top-right via `Positioned`
- Auto-dismisses after 4 seconds; swipe up to dismiss early; tap navigates to `MessageThreadScreen`
- Suppressed if `MessageThreadScreen` for that callsign is the current route (set via `NotificationService.setActiveThread`)

`InAppBannerController` is a `ChangeNotifier` that the overlay widget watches. Both it and `NotificationService` are added to the Provider tree in `main.dart`.

### `NotificationPreferences` (`lib/models/notification_preferences.dart`)

Immutable value object persisted to SharedPreferences (keys: `notif_channel_<id>`, `notif_sound_<id>`, `notif_vibration_<id>`). Defaults: all channels enabled; sound/vibration on for `messages` and `alerts`, off for `nearby` and `system`. `copyWithChannel`/`copyWithSound`/`copyWithVibration` return new instances; `NotificationService` holds the current instance and calls `notifyListeners()` after each update.

---

## Key Dependencies

| Package | Purpose |
|---|---|
| `flutter_map` | Map rendering with OpenStreetMap tiles |
| `flutter_blue_plus` | BLE transport (KISS/BLE) |
| `flutter_libserialport` | USB serial transport (KISS/USB) |
| `geolocator` | GPS/location access for beaconing (added v0.5) |
| `flutter_foreground_task` | Android foreground service keepalive (added v0.7) |
| `permission_handler` | Android permission requests (background location, notifications); iOS background location check (added v0.7, upgraded ^12.0.1 in v0.9) |
| `live_activities` | iOS Live Activity bridge — Dart → ActivityKit → Lock Screen / Dynamic Island (added v0.9) |
| `flutter_local_notifications` | System notification dispatch on Android, iOS, and macOS; inline reply via RemoteInput/UNTextInputAction (added v0.11) |
| `local_notifier` | Desktop system tray toast notifications on macOS, Windows, and Linux (added v0.11) |
| `provider` | ChangeNotifier wiring throughout service layer |
| `shared_preferences` | Theme mode, settings, beaconing config, and session state persistence |
| `dynamic_color` | Android 12+ wallpaper-derived ColorScheme |
| `m3e_design` | M3 Expressive ThemeExtension (shapes, spacing, motion, typography tokens) |
| `flutter_m3shapes` | M3 Expressive shape widgets (M3Container) |

No third-party APRS or AX.25 libraries — parsing is implemented in-house in the Packet Core.
