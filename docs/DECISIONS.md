# Architectural Decision Records

This file logs significant architectural decisions made during the development of Meridian APRS. New decisions should be appended in order.

---

## ADR-001: Flutter as Cross-Platform Framework

**Status:** Accepted

**Decision:** Build Meridian APRS with Flutter.

**Rationale:** A single Dart codebase targets all 6 platforms (iOS, Android, macOS, Windows, Linux, Web) from one repository. Flutter's widget model and strong ecosystem support make it viable for a production-quality APRS client without maintaining separate native codebases. The trade-off is platform-specific plugin availability for serial/BLE — acceptable given the plugin ecosystem (flutter_libserialport, flutter_blue_plus).

---

## ADR-002: GPL v3 License

**Status:** Accepted

**Decision:** License Meridian APRS under the GNU General Public License v3.

**Rationale:** GPL v3 ensures all derivatives remain open source, which is consistent with the broader APRS software ecosystem (Dire Wolf, Xastir, APRSDroid are all GPL). GPL v3 is compatible with Apple App Store distribution when the app is free. This keeps contributions flowing back to the community.

---

## ADR-003: OpenStreetMap via flutter_map

**Status:** Accepted

**Decision:** Use `flutter_map` with OpenStreetMap tile servers for map rendering.

**Rationale:** No API key required. Open data. OSM tile servers are freely available and well-maintained. `flutter_map` supports both online tile fetching and offline tile caching, leaving a clear path for future offline map support. Avoids vendor lock-in (Google Maps, Mapbox).

---

## ADR-004: APRS-IS Direct TCP (WebSocket Proxy for Web)

**Status:** Accepted

**Decision:** Connect to APRS-IS via direct TCP socket (`rotate.aprs2.net:14580`) on all platforms except web. On web, use a WebSocket-to-TCP proxy.

**Rationale:** Direct TCP avoids any third-party APRS-IS API dependency and gives full control over the connection (filter strings, keepalives, server rotation). The web platform cannot open raw TCP sockets — this is a hard browser security constraint. A WebSocket proxy is the standard workaround. The limitation is documented and acceptable; web is a secondary target platform.

---

## ADR-005: Pure Dart Packet Core

**Status:** Accepted

**Decision:** Implement all AX.25 framing and APRS parsing in pure Dart with no FFI.

**Rationale:** Pure Dart runs identically on all 6 Flutter platforms including web (which does not support dart:ffi). The performance of a pure-Dart parser is more than sufficient for APRS packet rates (typically <10 packets/second per filter). This maximizes portability and avoids build complexity from native libraries. Reference implementations (Dire Wolf, aprslib) serve as correctness oracles for test case generation, not as code to wrap.

---

## ADR-006: Layered Testing Strategy — TDD for Packet Core Only

**Status:** Accepted

**Decision:** Apply TDD exclusively to `lib/core/packet/` and `lib/core/ax25/`. Transport, service, and UI layers use test-after patterns in v0.1.

**Rationale:** Packet core is pure algorithmic logic with well-defined inputs (APRS protocol strings). Correctness is the primary concern and tests are fast to write and run. Transport/UI code is harder to test in isolation at this stage. TDD has high ROI in the core; test coverage for other layers will be added progressively in v0.2+.

---

## ADR-007: APRS Symbol Rendering — Material Icons with SymbolResolver (v0.1)

**Status:** Accepted

**Decision:** For v0.1, render APRS station symbols using Material Design icons mapped to common APRS symbol codes via a `SymbolResolver` class. Use the WB4APR APRS symbol table as the authoritative reference for symbol codes and human-readable names. Do not use Hessu's aprs.fi sprite sheets. Defer full sprite sheet integration to v1.0.

**Rationale:** Integrating a proper APRS symbol sprite sheet (PNG atlas or SVG set) requires bundling binary assets, writing sprite-region math, and handling all ~192 primary + 96 alternate symbols. For v0.1, Material Icons provide an immediately functional approximation for the most common station types (house, car, weather, aircraft, etc.) with zero asset dependencies. The `SymbolResolver` class is already in place with the full symbol-name mapping, so swapping in real sprite rendering at v1.0 is a contained UI change.

**Symbol licensing:** The WB4APR APRS symbol definitions are part of the public APRS specification. Community SVG recreations of the symbol set will be evaluated at v1.0 under their respective licenses. Hessu's aprs.fi sprite sheets are explicitly excluded — licensing terms for redistribution are unclear. Any sprite assets added in future must be permissively licensed (public domain, CC0, or MIT/Apache-compatible).

---

## ADR-008: AprsPacket Sealed Class Hierarchy

**Status:** Accepted

**Decision:** Model all decoded APRS packet types as a sealed class hierarchy rooted at `AprsPacket`, with concrete subtypes for each packet type: PositionPacket, WeatherPacket, MessagePacket, ObjectPacket, ItemPacket, StatusPacket, MicEPacket, and UnknownPacket.

**Rationale:** Sealed classes enable exhaustive switch dispatch at the UI layer without dynamic casting. The Dart compiler enforces that every subtype is handled at every switch site — omitting a case is a compile error, not a runtime surprise. The `UnknownPacket` catch-all ensures the parser never crashes on unrecognised input while still preserving the raw info field for debugging. This pattern scales cleanly as new packet types are added: adding a new subtype surfaces every switch that needs updating at compile time.

---

## ADR-009: AprsSymbolWidget — Deferred Symbol Rendering Swap

**Status:** Accepted

**Decision:** Abstract all APRS symbol rendering behind an `AprsSymbolWidget` widget. v0.2 uses Material icons (same approach as the v0.1 `SymbolResolver`). Full sprite sheet rendering is deferred to v1.0.

**Rationale:** Integrating a proper APRS symbol sprite sheet requires bundling binary assets and resolving licensing for any community-produced atlas. For v0.2, continuing to use Material icons avoids blocking packet log delivery on asset pipeline work. The `AprsSymbolWidget` abstraction isolates the rendering implementation: all call sites on the map and in the packet log use the widget, so the swap to a proper APRS bitmap atlas or SVG set at v1.0 is a one-file change with no ripple across the codebase.

---

## ADR-010: ThemeMode.system as Default

**Status:** Accepted

**Decision:** The default theme mode on first launch is `ThemeMode.system`, which follows the operating system's light/dark preference.

**Rationale:** On iOS the system default is light; on Android it varies by device and user preference. `ThemeMode.system` gives every user the experience that matches their existing OS choice without requiring any action during onboarding. Light and dark overrides are always available in Settings → Appearance. Persisting the choice to `SharedPreferences` ensures it survives restarts.

---

## ADR-011: Responsive Breakpoints at 600 px and 1024 px

**Status:** Accepted

**Decision:** The UI switches scaffold layout at two width thresholds: 600 px (mobile → tablet) and 1024 px (tablet → desktop).

**Rationale:** 600 px aligns with common Android and iOS breakpoints for "compact vs. medium" window sizes (Material Design 3 guidance) and represents the smallest typical tablet width in portrait. 1024 px aligns with typical laptop resolutions and wider iPad models in landscape. These breakpoints are widely used in the Flutter ecosystem and match the UI/UX spec. They are defined in `ResponsiveLayout` — changing them requires editing one file.

---

## ADR-012: Provider for ThemeProvider State Management

**Status:** Accepted

**Decision:** Use the `provider` package (specifically `ChangeNotifierProvider`) to expose `ThemeProvider` to the widget tree.

**Rationale:** `ThemeProvider` is the only piece of global app-level reactive state at this stage (theme mode). `provider` is already part of the Flutter recommended toolkit, has minimal API surface, and integrates cleanly with `ChangeNotifier`. The alternative — Riverpod — adds complexity not yet warranted by a single global notifier. If the app's state management needs grow significantly in v0.5+ (beaconing state, message drafts, connection state), migrating from `provider` to Riverpod is a contained refactor. Choosing `provider` now keeps dependencies lean and the architecture legible.

---

## ADR-013: SerialKissTransport Implements AprsTransport

**Status:** Accepted

**Context:** v0.3 adds USB serial TNC support. The existing `AprsTransport` abstract class (`lib/core/transport/aprs_transport.dart`) defines `Stream<String> get lines` — an APRS-IS text-line–oriented interface. An alternative was to introduce a new `TransportInterface` with `Stream<Uint8List>` for raw bytes, which would have required changes to `StationService` and the packet log.

**Decision:** `SerialKissTransport` implements `AprsTransport` directly. Internally it decodes KISS frames → AX.25 bytes → reconstructs an APRS-IS format line (`SOURCE>DEST,PATH:INFO`) and emits that on `lines`. `StationService` is unchanged.

**Consequences:** Minimal blast radius. No multi-transport refactor needed. The APRS line reconstruction is ephemeral (not stored). Failed AX.25 decodes emit an empty `rawLine` which `StationService._handleLine` silently skips.

---

## ADR-014: TncService Bridges to StationService via ingestLine

**Status:** Accepted

**Context:** Both APRS-IS and TNC should feed packets into the same station map and packet log. Options: (A) a public `ingestLine` method on `StationService`, or (B) refactor `StationService` to hold multiple transports.

**Decision:** Option A — `StationService.ingestLine(String raw)` is a thin public wrapper for `_handleLine`. `TncService` subscribes to `SerialKissTransport.lines` and calls `stationService.ingestLine(line)`.

**Consequences:** `StationService` API surface grows by one method. Multi-transport refactor is deferred until v0.5 beaconing requires it (when a transmit path is needed).

---

## ADR-015: TNC Preset System

**Status:** Accepted

**Context:** Serial port parameters (baud rate, parity, flow control) differ between TNC models. Free-form configuration is error-prone for common hardware.

**Decision:** `TncPreset` provides bundled presets for known hardware. Selecting any preset other than `custom` locks the serial parameter fields in the UI to prevent misconfiguration. The preset list (`TncPreset.all`) is a compile-time constant easily extended for v0.4 BLE presets.

**Consequences:** Adding a new TNC model requires adding a `const TncPreset` to `tnc_preset.dart`. Custom parameters remain available via the `custom` preset.

---

## ADR-016: flutter_libserialport for USB Serial

**Status:** Accepted

**Context:** USB serial access on desktop requires a platform plugin. Options: `flutter_libserialport`, `flutter_serial_port`, or raw platform channels.

**Decision:** `flutter_libserialport` (backed by `libserialport`) is chosen for its maturity, Linux/macOS/Windows support, and no FFI boilerplate. Version `^0.6.0` used (resolves to 0.6.0 / libserialport 0.3.0+1).

**Consequences:** Adds a desktop-only native dependency. Web and mobile are guarded by `dart.library.io` conditional export and the plugin's own platform manifest.

# ADR: Three-Tier Platform Theme Architecture

**Date:** 2026-03-21  
**Status:** Accepted  
**Deciders:** Eric (project lead)

---

## Context

Meridian targets Android, iOS, and desktop (Windows/macOS/Linux) from a single Flutter codebase. Each platform has a distinct native design language with different user expectations:

- Android users on modern Pixels expect Material You dynamic color (wallpaper-adaptive theming) and Material 3 Expressive styling.
- iOS users expect Cupertino design language — navigation transitions, system fonts, native chrome behavior.
- Desktop users have no strong per-OS UI expectation for a utility app; consistency across Windows/macOS/Linux is more valuable than per-OS native chrome.

The original UI Foundation theme system used a single `ThemeData` with static Meridian brand tokens — functional, but not platform-native on Android or iOS.

---

## Decision

Adopt a **three-tier platform theme architecture**:

| Tier | Platform | System |
|---|---|---|
| 1 | Android | Material 3 Expressive + Dynamic Color (`dynamic_color`, `m3e_design`) |
| 2 | iOS | Standard Cupertino (designed for clean Liquid Glass upgrade) |
| 3 | Desktop | Material 3 static brand theme (Meridian Blue seed, M3 only) |

A single `ThemeController` manages `themeMode` and `seedColor` as shared state. Platform detection (`Platform.isIOS`) occurs only at the app root to select `CupertinoApp` vs `MaterialApp`. All widgets below the root receive theme context normally.

---

## Consequences

**Android:** Users get full Material You integration — the app adapts to wallpaper colors on Android 12+ and gracefully falls back to a user-chosen seed color on older devices. M3 Expressive shapes and motion are applied via `m3e_design` ThemeExtension.

**iOS:** Users get a proper Cupertino experience today. The iOS theme is isolated in `lib/theme/ios_theme.dart` so that the upgrade to Liquid Glass (iOS 26+) is a contained, single-file change when Flutter's Cupertino library adds official support.

**Desktop:** A consistent, modern Material 3 appearance across all desktop platforms. No per-OS native chrome for now; this may be revisited post-v1.0 for macOS.

**Settings:** Android gains an App Color (seed) picker in Settings → Appearance, hidden on iOS and desktop. All platforms get a Theme mode toggle (System / Light / Dark), defaulting to System.

---

## Alternatives Considered

**Single unified Material 3 theme everywhere** — rejected because iOS users get a substandard experience (Material components do not feel native on iOS).

**Full per-platform native chrome (macOS native, Windows Fluent, etc.)** — rejected as disproportionate complexity for v1.0. Desktop users of a utility APRS app have lower native-feel expectations than mobile users.

**Static seed color on Android (no dynamic color)** — rejected because dynamic color is a flagship Android feature and core to the "modern ham" positioning of Meridian.

---

## Packages Added

| Package | Tier | Purpose |
|---|---|---|
| `dynamic_color` | Android | Wallpaper-derived ColorScheme on Android 12+ |
| `m3e_design` | Android | M3 Expressive ThemeExtension tokens |
| `flutter_m3shapes` | Android | M3 Expressive shape library |

---

## ADR-017: iOS Liquid Glass deferred pending Flutter framework support

**Status:** Accepted
**Date:** 2026-03-22

**Decision:** iOS Liquid Glass (Apple's glassmorphism design language, shipping with iOS 26 / visionOS 3) is intentionally not implemented in the v0.x iOS theme tier. The current `buildIosTheme()` function in `lib/theme/ios_theme.dart` provides the structural Cupertino foundation — `CupertinoApp`, `CupertinoThemeData`, Meridian brand primary color — without any Liquid Glass-specific APIs.

**Rationale:** Flutter's framework support for Liquid Glass is not yet available in the stable channel. The `docs/THEME_PLATFORM_STRATEGY.md` document outlines the intended upgrade path once stable framework APIs land.

**Consequences:** iOS UI uses standard Cupertino styling (system backgrounds, SF Pro) until an `ios-liquid-glass` feature branch is opened. No changes to the theme architecture are required when upgrading — `buildIosTheme()` will be extended in place.

---

## ADR-018: Desktop theme tier bypasses DynamicColorBuilder

**Status:** Accepted
**Date:** 2026-03-22

**Decision:** The desktop branch in `MeridianApp.build()` calls `buildDesktopTheme(seedColor: MeridianColors.primary)` directly without wrapping it in `DynamicColorBuilder`.

**Rationale:** `DynamicColorBuilder` returns null schemes on all desktop platforms (Windows, macOS, Linux); the wallpaper color extraction API is Android-only. Previously desktop fell through to the Android branch, which handled null schemes via the seed fallback — functional but implicit. Giving desktop its own explicit branch in `MeridianApp.build()` (`Platform.isWindows || Platform.isMacOS || Platform.isLinux`) makes the three-tier architecture fully explicit and removes the `DynamicColorBuilder` overhead on platforms where it does nothing. The desktop seed color is always `MeridianColors.primary` — there is no user-configurable color picker on desktop (the App Color section in Settings is Android-only).

**Consequences:** The three-tier platform theme architecture is now fully implemented. All three tiers — Android, iOS, Desktop — have dedicated `build*Theme()` functions and explicit platform branches at the app root. `DynamicColorBuilder` is used only in the Android branch.

---

## ADR-019: `KissTncTransport` — raw-frame interface for hardware TNCs (v0.4)

**Status:** Accepted
**Date:** 2026-03-22

**Decision:** Introduced `KissTncTransport` (`lib/core/transport/kiss_tnc_transport.dart`) as the contract for all hardware TNC transports. The interface emits `Stream<Uint8List>` (raw AX.25 bytes, KISS header stripped) rather than decoded APRS lines. APRS parsing (`AprsParser.parseFrame`) was moved from the transport layer into `TncService`.

**Rationale:** Transports should not know about APRS application semantics. A byte-level interface allows both serial and BLE transports to be tested at the framing layer without coupling to APRS logic. It also enables future transports (e.g., TCP KISS, soundcard TNC) to plug in without touching the service layer. `TransportManager` was introduced as the single holder of the active `KissTncTransport`, bridging its streams to callers and managing lifecycle (connect/disconnect, type tracking).

**Consequences:** `SerialKissTransport` now implements `KissTncTransport` (was `AprsTransport`). `TncService` owns a `TransportManager` and an `AprsParser` — it calls `parseFrame(frameBytes)` on each AX.25 frame received from the active transport and feeds the resulting APRS line to `StationService`. The `AprsTransport` interface is now used exclusively by `AprsIsTransport` (APRS-IS over TCP/WebSocket).

---

## ADR-020: BLE chunking via MTU negotiation (v0.4)

**Status:** Accepted
**Date:** 2026-03-22

**Decision:** `BleTncTransport` requests MTU 512 during `connect()`. The effective outgoing chunk size is `max(20, negotiatedMtu - 3)` (subtracting 3 bytes of ATT overhead). If MTU negotiation fails the transport falls back to 20-byte chunks. Outgoing KISS frames are split into MTU-sized chunks and written sequentially with `withoutResponse: false` (write-with-response) for backpressure. Incoming BLE notification chunks are reassembled by the existing `KissFramer` — no new framing logic.

**Rationale:** BLE GATT write operations are bounded by the ATT MTU. Mobilinkd TNC4 supports MTU 512, giving ~509-byte write payloads — large enough for any single AX.25 frame without chunking in practice. The fallback to 20 bytes ensures compatibility with devices that do not negotiate a larger MTU. Using write-with-response prevents flooding the TNC's receive buffer. Reusing `KissFramer` for reassembly means the BLE path has the same reassembly correctness guarantees as the serial path (verified by 23 existing KissFramer tests).

**Consequences:** `BleTncTransport` is the primary TNC transport for iOS and Android. Mobilinkd TNC4 is the primary tested device. `BleDeviceAdapter` (an abstract interface mirroring `SerialPortAdapter`) allows `BleTncTransport` to be unit-tested with a `FakeBleDeviceAdapter` without requiring a physical BLE stack.

---

## ADR-021: SmartBeaconing algorithm and defaults (v0.5, revised v0.7)

**Status:** Accepted
**Date:** 2026-03-28 (revised 2026-03-30)

**Decision:** `SmartBeaconing.computeInterval` uses the original HamHUD inverse-proportional formula (`fastRate × fastSpeed / speed`), not linear interpolation. `SmartBeaconing.turnThreshold` divides `turnSlope` by speed in **mph** (not km/h), matching the units of the original SmartBeaconing™ specification. `SmartBeaconingParams.defaults` uses: fastSpeed=100 km/h, fastRate=180 s, slowSpeed=5 km/h, slowRate=1800 s, minTurnTime=15 s, minTurnAngle=28°, turnSlope=255.

**Rationale:** The inverse-proportional formula keeps beacon density (beacons per km travelled) roughly constant across speeds. Linear interpolation under-beacons at moderate speeds (30–80 km/h) by 2–3× compared to the original spec and hardware TNCs. The `turnSlope` parameter has units of degrees·mph in every reference implementation (Dire Wolf, APRSdroid, HamHUD); dividing by km/h makes turn detection ~60% too sensitive. The default parameter values are close to Dire Wolf's defaults and the original HamHUD defaults. APRSdroid uses different defaults (fastRate=60 s, slowRate=1200 s, minTurnAngle=10°, turnSlope=240) and linear interpolation — Meridian's more conservative defaults reduce channel load while still producing good tracks.

**Consequences:** `SmartBeaconingParams` is a `const` value object; `defaults` is a `static const`. Users can override all parameters via the Beaconing settings screen; the Reset Defaults button restores these values.

---

## ADR-022: Message retry backoff = APRS spec §14 intervals (v0.5)

**Status:** Accepted
**Date:** 2026-03-28

**Decision:** `MessageService` retries unacked outbound messages at fixed delays of 30, 60, 120, 240, and 480 seconds (5 attempts total). After the 5th retry without acknowledgement, the message status transitions to `failed`.

**Rationale:** APRS spec §14 recommends retrying unacknowledged messages at increasing intervals but does not mandate specific values. The 30/60/120/240/480 sequence is the most common implementation in the APRS ecosystem (seen in Dire Wolf, APRSdroid, and Xastir). Using the same intervals keeps interoperability predictable — a far-end station implementing the same backoff will not flood the channel with simultaneous retransmissions.

**Consequences:** Each pending message holds one `Timer`. On ACK or REJ receipt the timer is cancelled. After `failed`, the user must manually resend. The total window before failure is ~15 minutes, which is intentionally long to handle intermittent connectivity.

---

## ADR-023: Global (not per-station) TX transport preference (v0.5)

**Status:** Accepted
**Date:** 2026-03-28

**Decision:** `TxService` holds a single `TxTransportPref { auto, aprsIs, tnc }` that applies to all outgoing packets — position beacons and messages alike. There is no per-destination or per-packet-type override.

**Rationale:** Amateur radio operators almost always have one TX path available at a time (either connected to a TNC or not). A per-packet or per-destination preference would add UI complexity with no real-world benefit for the v0.5 use case. `auto` mode (default) provides sensible behaviour: use TNC when connected, fall back to APRS-IS otherwise. Advanced users who want explicit control can select `aprsIs` or `tnc` in Settings.

**Consequences:** `TxService` subscribes to `TncService.connectionState`. On TNC disconnect while the effective transport is TNC, it emits `TxEventTncDisconnected` (drives a banner) without persisting a fallback — the stored preference remains `tnc` so the switch-back offer can be presented on reconnect. This means a TNC disconnection while Meridian is backgrounded is surfaced to the user on next interaction rather than silently discarded.

---

## ADR-024: Connection as first-class navigation destination (v0.6)

**Status:** Accepted
**Date:** 2026-03-29

**Decision:** Replace the `ConnectionSheet` modal bottom sheet with a full-screen `ConnectionScreen` as a proper navigation destination in all three scaffold tiers. On mobile it becomes the 5th `NavigationBar` item; on tablet/desktop the existing transient rail item is converted to a real `IndexedStack` child.

**Rationale:** The previous modal sheet required users to know to tap the AppBar status pills or the rail item to manage connections — there was no persistent visual affordance beyond a small pill. As the app gains BLE and serial TNC support alongside APRS-IS, connection management grows in complexity (multiple active transports, TX routing, per-transport connect/disconnect). A dedicated screen with a reactive nav icon is a more appropriate container. A modal sheet that is growing in complexity is a sign it should become a screen.

**Key sub-decisions:**
- `ConnectionNavIcon` uses `Selector2<StationService, TncService, ...>` (not `Consumer2`) to avoid rebuilding on every ingested packet.
- BLE tab lazy-instantiates `BleScannerSheet` via `if (_tab == 1)` rather than an `IndexedStack`, preventing the Bluetooth permission check from firing before the user navigates to that tab.
- APRS-IS server/port/filter fields remain read-only for v0.6 — `AprsIsTransport` is constructed once in `main.dart` with hardcoded defaults. Mutable server config is deferred to v0.7.
- On desktop, `_ConnectionStatusChip` in the AppBar replaces the two separate `MeridianStatusPill` widgets with a single combined chip showing "APRS-IS + TNC", "APRS-IS", "TNC", or "Not connected".
- The map screen's "not connected" nudge (Branch 2) uses `Navigator.push(ConnectionScreen)` as a full-screen route rather than a callback to switch the scaffold's nav index. This avoids coupling `MapScreen` to scaffold internals and works correctly across all three breakpoints.

**Consequences:** `ConnectionSheet` is retained but no longer wired to any nav action — it can be deleted in a cleanup PR once confirmed unused. `StationService` must be provided via the `Provider` tree (not just passed as a constructor arg to `MapScreen`) so that `ConnectionScreen` can access it from `context`; the widget test was updated accordingly.

---

## ADR-025: Android foreground service via flutter_foreground_task (v0.7)

**Status:** Accepted
**Date:** 2026-03-30

**Decision:** Add an Android foreground service using `flutter_foreground_task ^8.x`. The service is a "process keepalive only" — it does not contain any transport or beaconing logic. All application logic continues in the main Dart isolate via the existing service layer (`TncService`, `StationService`, `BeaconingService`), which the foreground service prevents from being killed.

A new `BackgroundServiceManager` ChangeNotifier on the main isolate manages the lifecycle and drives notification content via `FlutterForegroundTask.updateService()` (not via round-trips through the background isolate). The `MeridianConnectionTask` (`TaskHandler`) in the background isolate contains no app logic — its `onRepeatEvent` fires a 60-second heartbeat to keep aggressive OEM firmware from killing the service.

**Key sub-decisions:**

- `ChangeNotifierProvider(create:)` + `addListener` in constructor for dependency wiring — not `ChangeNotifierProxyProvider3`, which would recreate the manager on every dependency notification.
- `FlutterForegroundTask.updateService()` called directly from the main isolate (not via `sendDataToTask()` round-trip) — simpler and correct.
- `ACCESS_BACKGROUND_LOCATION` permission check placed in `BackgroundServiceManager.requestStartService(BuildContext)` — stays at the UI-initiation boundary, keeps `BeaconingService` free of Android-specific permission handling.
- `minSdk` hardcoded to 21 in `build.gradle.kts` (required by `flutter_foreground_task`; previously `flutter.minSdkVersion` which resolves to 16).
- `FOREGROUND_SERVICE_CONNECTED_DEVICE`, `FOREGROUND_SERVICE_LOCATION`, and `FOREGROUND_SERVICE_DATA_SYNC` added with `android:minSdkVersion="34"` guard — silently ignored on lower API levels. `android:foregroundServiceType="dataSync|location|connectedDevice"` on the service element matches the permissions so the service can serve both auto/smart beaconing (location) and BLE TNC keepalive (connectedDevice). The `connectedDevice` type was initially missing from the manifest; corrected in v0.13 (issue #44) — see ADR-047.
- `ForegroundServiceApi` injectable interface added to `BackgroundServiceManager` so the state machine can be unit-tested without platform channel dependencies.
- `autoRunOnBoot: false` — the service does not automatically restart after device reboot.

**Consequences:** Transport connections and beaconing remain active when Meridian is backgrounded on Android. A persistent notification appears in the status bar (required by Android; cannot be dismissed while service runs). The `ConnectionScreen` shows a background-service section (Android-only) with a toggle and status indicator. `ConnectionNavIcon` shows a badge dot when the service is running. iOS background beaconing is deferred to v0.9.

---

## ADR-026: ACCESS_BACKGROUND_LOCATION permission flow (v0.7)

**Status:** Accepted
**Date:** 2026-03-30

**Decision:** The `ACCESS_BACKGROUND_LOCATION` check and request lives in `BackgroundServiceManager.requestStartService(BuildContext)`. The flow is:

1. If beaconing mode is not `manual`, check `Permission.locationAlways.status` via `permission_handler`.
2. If not granted: show `AlertDialog` explaining that "Allow all the time" location access is needed.
3. Call `Permission.locationAlways.request()` — on Android 11+ this opens the system Settings page (OS no longer allows in-app dialogs for background location).
4. If the user denies, `requestStartService` returns `false` and sets `state = BackgroundServiceState.error`.

`BeaconingService.startBeaconing()` is unchanged — it continues to manage `ACCESS_FINE_LOCATION` via `Geolocator.requestPermission()`.

**Rationale:** Google Play policy (as of August 2020) requires an explicit rationale dialog before requesting background location. Bundling this into `BeaconingService` would couple a UI concern (dialog display) to a service-layer class. Placing it at the call site (`requestStartService`) keeps the service layer free of BuildContext dependencies while ensuring the rationale is shown at the right moment — when the user explicitly enables background service, not on app launch.

**Consequences:** Background location is only requested when the user enables the background service with non-manual beaconing configured — compliant with Google Play's "least privilege" policy. Users who only use manual beacon mode or APRS-IS receive-only are never prompted for background location.

---

## ADR-027: Tile provider — Stadia Maps (v0.8)

**Status:** Accepted
**Date:** 2026-04-04

**Decision:** Replace public OSM/CartoDB tile URLs with Stadia Maps (`alidade_smooth` for light mode, `alidade_smooth_dark` for dark mode). Tile URLs are routed through a `MeridianTileProvider` abstraction (`lib/map/`) so the provider can be swapped with minimal changes in future milestones (e.g., `flutter_map_tile_caching` for offline support). The API key is injected at build time via `--dart-define=STADIA_MAPS_API_KEY` and is never committed to source.

**Key sub-decisions:**
- `MeridianTileProvider` abstract class with a single `tileUrl(Brightness)` method — keeps the tile-URL computation out of the widget tree.
- `StadiaTileProvider` is a const-constructible implementation; the instance lives on `_MapScreenState` as a final field.
- Brightness is resolved from `ThemeController.themeMode` in `MapScreen.build()` and passed down — consistent with the existing pattern for other theme-aware decisions.
- CartoDB-specific `_usesSubdomains` + brightness-boost `ColorFilter.matrix` removed from `MeridianMap` — these were workarounds for CartoDB's near-black dark tiles, which Stadia does not require.
- `RichAttributionWidget` added to `FlutterMap.children` — Stadia Maps requires attribution for OSM, OpenMapTiles, and Stadia itself.
- `AppConfig.stadiaMapsApiKey` uses `String.fromEnvironment` with `defaultValue: ''` — the app will run without tiles (blank map) if the key is not provided, rather than crashing.

**Rationale:** Public OSM tile servers are rate-limited and prohibited for production app use per OpenStreetMap ToS. Stadia Maps free tier explicitly covers non-commercial open-source projects. The `alidade_smooth` / `alidade_smooth_dark` styles are visually neutral, low-noise, and appropriate for overlaying APRS station data. Stadia is privacy-focused (no user tracking) and GDPR/CCPA compliant.

**Consequences:** Developers must pass `--dart-define=STADIA_MAPS_API_KEY=<key>` to run the app locally (documented in CLAUDE.md and `.env.example`). CI uses a `STADIA_MAPS_API_KEY` GitHub Actions secret. The `MeridianTileProvider` abstraction is the designated extension point for future offline caching — do not bypass it.

---

## ADR-028: iOS platform routing pattern (v0.8)

**Status:** Accepted
**Date:** 2026-04-04

**Decision:** Introduce `buildPlatformRoute<T>(WidgetBuilder)` in `lib/ui/utils/platform_route.dart`. On iOS (`!kIsWeb && Platform.isIOS`) it returns a `CupertinoPageRoute`; on all other platforms it returns a `MaterialPageRoute`. All imperative push navigations use this helper. All `TODO(ios): CupertinoPageRoute` markers are removed when the site is updated.

**Key sub-decisions:**
- Single free function (not a class, not an extension) — simplest possible API for a one-argument call site.
- Generic `<T>` preserves the push return type used by `LocationPickerScreen` (returns `LatLng?`).
- The three `TODO(ios): replace with Cupertino search UI` markers in scaffold files are deferred — they require a redesign of the `SearchDelegate` surface, not just a route swap.
- The `MaterialBanner` in `MapScreen` (`TODO(ios): use Cupertino-styled banner`) is deferred — no direct Cupertino equivalent exists; requires a custom overlay in a future pass.

**Rationale:** `MaterialPageRoute` on iOS produces left-to-right slide transitions instead of the native right-edge swipe-to-go-back behavior of `CupertinoPageRoute`. Without this fix, the iOS swipe-back gesture does not trigger pop on any screen that was pushed via `MaterialPageRoute`, which is immediately noticeable and jarring for iOS users.

**Consequences:** All future push navigations in the app must use `buildPlatformRoute` rather than `MaterialPageRoute` directly. The three deferred `TODO(ios)` markers remain until their respective UIs are redesigned.



---

## ADR-029: ConnectionRegistry abstraction (v0.9 prep)

**Status:** Accepted
**Date:** 2026-04-11

**Decision:** Replace the paired `TncService` + `StationService` transport management pattern with a `ConnectionRegistry` holding a list of `MeridianConnection` objects (`AprsIsConnection`, `BleConnection`, `SerialConnection`). Each connection owns its own lifecycle, AX.25 decoding, and beaconing enable/disable toggle. `StationService` is reduced to a pure packet ingestion and state aggregation service; `TxService` routes through the registry. `TncService` and `TransportManager` are deleted.

**Key sub-decisions:**
- `MeridianConnection extends ChangeNotifier` with `connect/disconnect/sendLine/lines/beaconingEnabled` — uniform interface regardless of transport protocol.
- `ReconnectableMixin` centralises exponential-backoff reconnect logic (2→4→8→16→30s, 5 retries) shared between `BleConnection` and `AprsIsConnection`; `SerialConnection` has no reconnect (user-initiated).
- Each TNC connection normalises AX.25 bytes to APRS text strings internally, so `StationService.ingestLine` remains a plain string API.
- `ConnectionRegistry.lines` is a merged `Stream<({String line, ConnectionType source})>` — single subscription point for `StationService`.
- Per-connection beaconing toggle replaces the previous global `TxTransportPref {auto, aprsIs, tnc}` enum; `BeaconingService.sendBeacon` fans out to all connections with `beaconingEnabled && isConnected`.
- `TxService.sendLine` resolves a TX hierarchy (Serial > BLE > APRS-IS) for message sending, with a `forceVia: ConnectionType?` per-message override.
- Platform availability is gated inside each connection class (`BleConnection.isAvailable` = Android/iOS; `SerialConnection.isAvailable` = Linux/macOS/Windows); `ConnectionRegistry.available` filters accordingly.
- `BackgroundServiceManager` now observes `ConnectionRegistry` + `BeaconingService`; per-connection `_reconnectTimers` map replaces per-transport boolean flags. BLE is excluded from BSM reconnect because `BleConnection` self-manages via `ReconnectableMixin`.
- `PacketSource` enum gains `bleTnc` and `serialTnc` variants; `tnc` is kept as a legacy deserialization alias.

**Alternatives considered:**
- **Global service pair** (keep `TncService` + add `AprsIsService`): rejected — adding a 4th connection type would require a 3rd service and more cross-service coordination.
- **Adapter-only layer** (registry of transport adapters, services remain): rejected — services would still need to know about each adapter type individually for beaconing and TX routing.

**Consequences:**
- Adding a new connection type (e.g., TCP/IP Direwolf) = create one `MeridianConnection` subclass and `registry.register(conn)` in `main.dart`.
- `TncService` and `TransportManager` are deleted; their test files are also removed. Existing serial/BLE tests are re-implemented in `test/core/connection/`.
- `connection_screen.dart` builds tabs dynamically from `registry.available` — no platform guards needed in the UI.
- The `TODO(tocall)` markers for the APZMDN placeholder have been removed; `APMDN0` is the official tocall (allocated 2026-04-19, see ADR-046).

---

## ADR-030: VoIP UIBackgroundMode for APRS-IS TCP persistence on iOS

**Status:** Accepted
**Date:** 2026-04-11

**Decision:** Declare `voip` in `UIBackgroundModes` (alongside `bluetooth-central` and `location`) to keep the iOS process alive while the app is backgrounded with an active APRS-IS TCP connection.

**Rationale:** iOS aggressively suspends apps without a declared background mode. `voip` is the closest semantic match to APRS-IS (a persistent bidirectional TCP stream), gives the OS permission to keep the process alive when a network connection is active, and pairs with `bluetooth-central` to keep BLE TNC connections alive. With `location` declared and "Always" permission granted, background GPS updates keep the process alive for SmartBeaconing.

**Alternatives considered:**
- `BGTaskScheduler`: Limited to 30-second processing windows, no persistent TCP socket support — unsuitable for continuous packet reception.
- Silent push notifications: Requires a server to send push; introduces infrastructure dependency; iOS delivers these at system discretion and may coalesce or drop them.
- Background URL sessions: HTTP/HTTPS only — APRS-IS uses raw TCP, not HTTP.

**Consequences:**
- App Store review may scrutinize the `voip` mode for an APRS client. APRS-IS is a real-time radio packet stream, which is a legitimate VoIP-analogous use case; the description should make this clear in the App Store listing.
- `setMinimumBackgroundFetchInterval(backgroundFetchIntervalMinimum)` is set in `AppDelegate` to supplement the VoIP keepalive with background fetch opportunities.

---

## ADR-031: `live_activities` Flutter package over raw ActivityKit bridge

**Status:** Accepted
**Date:** 2026-04-11

**Decision:** Use the `live_activities` pub.dev package (v2.4.7) to bridge Flutter to iOS ActivityKit, rather than writing a custom `FlutterMethodChannel` bridge.

**Rationale:** The `live_activities` package provides a tested Dart API (`createActivity`, `updateActivity`, `endActivity`) that accepts `Map<String, dynamic>` and handles the Swift-side `LiveActivitiesAppAttributes` transport internally via an App Group file share. Writing and maintaining a custom ActivityKit bridge in Swift + a corresponding Dart method channel would require significant ongoing maintenance as ActivityKit evolves.

**Alternatives considered:**
- **Custom FlutterMethodChannel**: Full control but high maintenance cost; duplicates what the plugin already does correctly.
- **Push-to-start Live Activities**: Requires APNs push infrastructure on a server; out of scope for a self-contained ham radio app.

**Consequences:**
- Dependency on `live_activities: ^2.4.7` (and its transitive dependency on `permission_handler ^12.0.1`, which prompted upgrading from `^11.4.0`).
- An App Group (`group.com.meridianaprs.meridianAprs`) must be created in the Apple Developer portal and enabled on both the Runner and widget extension targets. This is a one-time developer portal step — not automatable from code.
- The Live Activity UI (`MeridianLiveActivityLiveActivity`) is implemented in SwiftUI in the `MeridianLiveActivity` widget extension target.

---

## ADR-032: No separate background isolate on iOS — main isolate continues

**Status:** Accepted
**Date:** 2026-04-11

**Decision:** On iOS, the main Dart isolate continues running in the background (via `voip` + `bluetooth-central` + `location` UIBackgroundModes). No separate `MeridianConnectionTask`-style background isolate is started on iOS.

**Rationale:** Android kills the UI process when the app is backgrounded, which necessitates the `flutter_foreground_task` foreground service and the `MeridianConnectionTask` background isolate. iOS's model is different: with the right UIBackgroundModes declared and active connections in use, iOS suspends the app much less aggressively and the main Dart isolate continues to run. `ConnectionRegistry`, `BeaconingService`, and `TxService` — all running on the main isolate — remain active and continue packet reception and beacon firing without any isolate boundary.

**Consequences:**
- `IosBackgroundService` is a lightweight `ChangeNotifier` that manages the Live Activity and background location permission signalling; it does not start any isolate or foreground service.
- `MeridianConnectionTask` is Android-only and remains unchanged.
- If Apple tightens background execution policies in a future iOS release, this architecture may need to be revisited (e.g., migrating to `BGProcessingTask` for beaconing).

---

## ADR-033: Viewport-adaptive APRS-IS bounding-box filter

**Status:** Accepted
**Date:** 2026-04-12

**Decision:** Replace the fixed-radius `#filter r/LAT/LON/RADIUS` APRS-IS filter with a viewport-derived bounding-box `#filter a/N/W/S/E` filter. The bounding box is computed from the visible map area, padded 25% on each edge, with a minimum half-extent of ≈0.45° (≈50 km) enforced on each axis. The filter is sent on map camera-idle with a 500 ms debounce. At connect time a default 1.5° half-extent box centred on the last-known map position is used.

**Rationale:** A fixed-radius filter returns a circular region regardless of the device's screen orientation, aspect ratio, or zoom level. At high zoom a 150 km radius grossly over-fetches; at low zoom it under-fetches the visible area. A bounding box matches the actual screen geometry and scales automatically with zoom. The 25% padding prefetches stations that are just outside the visible edge so panning feels instant. The 50 km minimum floor prevents the filter from becoming uselessly small on very close zooms.

**Filter syntax note:** The APRS-IS area filter is `a/latN/lonW/latS/lonE` (javAPRS/aprsc spec at aprs-is.net/javAPRSFilter.aspx). `b/` is the *budget* (callsign) filter — using `b/` with lat/lon coordinates produces a syntactically valid but geographically useless filter that matches no callsigns and delivers no packets, even though the server confirms it "active". Always use `a/` for geographic bounding boxes.

**Alternatives considered:**
- **Keep fixed radius**: Simple but wastes bandwidth on very large radii at high zoom; under-fetches at low zoom.
- **Radius computed from bounding-box diagonal**: Numerically equivalent to a bounding box but loses directional specificity; server supports `a/` directly so there is no reason to convert.

**Consequences:**
- `AprsIsConnection.updateFilter` now takes `LatLngBounds` instead of `(double lat, double lon, {int radiusKm})`. Callers (map_screen.dart, tests) updated accordingly.
- The static helper `AprsIsConnection.defaultFilterLine(lat, lon)` is exposed for use at connect time when no viewport bounds are available.
- Filter format is `a/N/W/S/E` (North, West, South, East) as per the APRS-IS specification.

---

## ADR-034: Time filter default of 60 min and position history cap of 500 entries

**Status:** Accepted
**Date:** 2026-04-12

**Decision:** Default the station display time filter (`stationMaxAgeMinutes`) to 60 minutes. Cap per-station position history at 500 entries. Store the time filter in SharedPreferences under `station_max_age_minutes`; absence of the key is treated as "use default (60)" on first launch.

**Rationale:** A 1-hour window matches the typical expectation for what "currently active" means on APRS — a station heard more than an hour ago is unlikely to still be at that position. It also keeps the station count manageable on busy APRS networks (e.g. urban APRS-IS feeds with hundreds of stations per hour).

The 500-entry history cap prevents unbounded memory growth for high-speed mobile stations (e.g. aircraft). At one packet per minute, 500 entries covers ≈8 hours — more than the maximum supported time filter window (12 hours). The cap is enforced on every position update; it does not require a periodic sweep.

**Consequences:**
- First-run users see at most 60 minutes of history; users who previously ran without a filter will see their station map trimmed on the first prune pass.
- Position history is not persisted across app restarts (only `lat`/`lon`/`lastHeard` are serialised). This is acceptable — history rebuilds organically as new packets arrive.

---

## ADR-035: Main-isolate notification dispatch — no cross-isolate path needed

**Status:** Accepted
**Date:** 2026-04-18

**Decision:** `NotificationService` subscribes to `MessageService` on the main Dart isolate and dispatches system notifications from there. No cross-isolate communication path is implemented for notification delivery.

**Rationale:** The `flutter_foreground_task` `TaskHandler` (`MeridianConnectionTask`) is a beaconing heartbeat only — it does not process incoming APRS packets. All packet ingestion, `StationService` updates, and `MessageService` listener callbacks run on the main Dart isolate. On Android, the foreground service (declared via `flutter_foreground_task`) keeps the main isolate alive when backgrounded. On iOS, the `voip` UIBackgroundMode keeps the process alive. In both cases, a simple `messageService.addListener` fires reliably while backgrounded, so no background-isolate notification path is needed.

The handoff spec described a "background isolate" dispatch path — this was based on a misread of the architecture. Correcting it here so future implementers don't build a cross-isolate path that's unnecessary and more fragile.

**Consequences:** `NotificationService.initialize()` must be called before `runApp()` so the listener is wired before the first background event. The `@pragma('vm:entry-point')` `onNotificationBackgroundResponse` top-level function handles the one true background-isolate case: Android inline reply when the app process is **terminated** (not just backgrounded). In that case, the app is cold-launched in a background context; the handler writes the reply to a SharedPreferences outbox that `_drainReplyOutbox()` processes on the next main-isolate startup.

---

## ADR-036: InAppBannerOverlay at the app root rather than per-screen

**Status:** Accepted
**Date:** 2026-04-18

**Decision:** `InAppBannerOverlay` wraps the `home` widget in `MeridianApp.build()` — a single insertion point that covers every screen.

**Rationale:** Placing the banner per-screen (e.g. only in `MapScreen`) would require every screen that could receive a message while active to replicate the overlay code. APRS messages can arrive while the user is on the Packet Log, Station List, Settings, or Connection screen. A single root-level overlay costs nothing extra (it's a `Stack` with a conditionally-visible child) and requires zero per-screen wiring.

**Alternatives considered:**
- Overlay entry via `Navigator.of(context).overlay.insert(...)`: more powerful, but harder to dismiss cleanly and requires a reference to the navigator at insertion time.
- `ScaffoldMessenger.of(context).showSnackBar(...)`: zero custom code, but SnackBar appears at the bottom, lacks callsign+preview layout, and cannot carry tap-to-navigate behavior without a custom SnackBar widget.

**Consequences:** `InAppBannerController` must be provided above the `MeridianApp` builder (i.e., in the `MultiProvider` in `main.dart`) so `InAppBannerOverlay` can access it.

---

## ADR-037: System notification fires even while app is foregrounded

**Status:** Accepted
**Date:** 2026-04-18

**Decision:** System notifications (via `flutter_local_notifications`) are dispatched regardless of whether the app is in the foreground. On iOS, `DarwinInitializationSettings` sets `presentAlert: true` and `presentSound: true` for foreground delivery.

**Rationale:** Meridian is a radio communications tool. Missed messages have real operational consequences — the user may be looking at the map or a different screen and would not notice an incoming message without an audible/visual alert. Both the in-app banner and the system notification fire independently; they serve different user attention states (foreground awareness vs. OS-level intrusion).

**Alternatives considered:**
- Suppress system notification when app is foregrounded (common in chat apps): rejected because foreground ≠ "user is looking at the message thread". The user could be watching the map while a message comes in.
- Fire only the in-app banner in foreground: rejected for the same reason — the banner is visual-only and could be missed.

**Consequences:** Users may see both the banner and the notification center entry simultaneously when foregrounded. This is intentional and matches the behavior of push-to-talk and emergency communications apps.

---

## ADR-038: Desktop inline reply not implemented

**Status:** Accepted
**Date:** 2026-04-18

**Decision:** Desktop platforms (macOS, Windows, Linux) do not support inline reply from the notification. Tapping a desktop toast navigates to `MessageThreadScreen` for the reply.

**Rationale:** `local_notifier` (the desktop toast library) does not expose a text input action API. macOS `UNUserNotificationCenter` does support text input replies, but wiring it through `local_notifier` → Dart would require a custom platform channel, which is out of scope for v0.11. The `flutter_local_notifications` package also does not support Windows or Linux notifications. Desktop APRS operators typically have the app visible on screen — the click-to-navigate flow is adequate.

**Future path:** If macOS inline reply becomes a priority, it can be implemented via a custom Swift platform channel that registers a `UNTextInputNotificationAction`, fires the reply into a named `ReceivePort` on the main isolate, and calls `MessageService.sendMessage`. This is a discrete addition that does not require changing the `NotificationService` dispatch path.

---

## ADR-039: Brand Color Change to Meridian Purple

**Status:** Accepted
**Date:** 2026-04-18

**Decision:** Change the Meridian brand seed color from `#2563EB` (Meridian Blue) to `#4D1D8C` (Boosted Purple). Expand the brand color file into a full tonal palette plus harmonized neutrals, replacing the two-constant `primary`/`primaryDark` API.

**Rationale:**
- The app icon locked in as a purple pin; brand seed must match the icon to be coherent.
- Purple is distinctive in the APRS/ham-radio tooling space — no major competitor owns it.
- A full tonal palette provides stable tokens for UI work that don't depend on dynamic-color output (splash, about, onboarding brand-tinted surfaces).
- Warm-tinted neutrals (vs. pure gray) tie the UI back to the brand hue subtly.

**Scope of change:**
- `MeridianColors.brandSeed` replaces `MeridianColors.primary` as the brand anchor.
- `MeridianColors.primaryDark` removed (was unused); `brandPurple` removed (superseded by `brandSeed`).
- Full tonal palettes added as static tokens (`brand`, `neutral`, `neutralVariant`).
- Semantic colors (`signal`, `warning`, `danger`) retained with original hex values.
- New `info` semantic color added (`#3B82F6`).
- Default App Color swatch updated to Meridian Purple; Violet swatch replaced with Indigo (`#4F46E5`) to avoid near-duplication with the new brand.

**Unchanged:**
- Material You dynamic color behavior on Android 12+.
- User-selectable App Color picker on Android.
- Theme mode toggle (System / Light / Dark) on all platforms.
- iOS Cupertino theme tier.
- Desktop static M3 tier (seed value changes, structure does not).
- Semantic color values and the rule against dynamic-color shifting.

**Alternatives considered:**
- Keep Meridian Blue — rejected; mismatch with purple icon would be incoherent.
- Pin theme primary to the literal seed — rejected in favor of M3 convention (`ColorScheme.fromSeed` selects its own primary tone, which is standard M3 behavior).

---

## ADR-040: Wordmark & Inter Font Integration

**Status:** Accepted
**Date:** 2026-04-18

**Decision:** Bundle Inter TTFs offline in `assets/fonts/`. Bundle 5 wordmark SVG variants in `assets/wordmarks/`. Expose via `MeridianWordmark` widget with five named constructors. Use wordmark only in canonical brand moments: splash background, onboarding welcome, about screen, README.

**Rationale:**
- Offline bundling ensures consistent rendering in low-connectivity environments (core APRS use case).
- Inter is reserved for the wordmark specifically — full app typography stays on platform defaults (M3/Roboto on Android, SF Pro on iOS, M3 default on desktop).
- Wordmark does not appear in app bars; those show screen titles for navigation clarity.
- iOS launch screen is icon-only per Apple HIG; wordmark appears on first in-app screen (onboarding welcome).
- Android 12+ native splash is icon-only per Google guidance; pre-12 fallback via `flutter_native_splash`.
- Five named constructors (horizontal, stacked, horizontalMono, horizontalMonoWhite, stackedMono) provide clear intent at call sites.

**Alternatives considered:**
- `google_fonts` runtime loading — rejected; offline-first requirement.
- Inter as app default typography — rejected; scope creep, separate concern.
- Wordmark in app bars — rejected; app bars belong to screen navigation.
- `lib/widgets/` top-level directory — rejected; project convention is `lib/ui/widgets/`.

---

## ADR-041: Dark-Mode Brand Asset Switching

**Status:** Accepted
**Date:** 2026-04-18

**Decision:** Add dark-mode SVG variants of the pin icon and primary wordmarks. `MeridianWordmark.horizontal()` and `MeridianWordmark.stacked()` auto-select the dark variant when `Theme.of(context).brightness == Brightness.dark`. A new `MeridianIcon` widget does the same swap for standalone pin renders. Native splash screens are updated with dark-mode PNG variants via `flutter_native_splash`.

**Rationale:**
- brand040 (`#4D1D8C`) has insufficient contrast against dark surfaces (≈1.7:1 vs neutral010 — fails WCAG).
- brand080 (`#C8B0E8`) provides ≈5.7:1 contrast against neutral010 dark backgrounds — passes WCAG AA for UI components.
- Preserves brand identity: the pin and wordmark remain unmistakably purple-family in both modes.
- Material 3 already shifts the primary role from tone 40 (light) to tone 80 (dark) for `ColorScheme.fromSeed()` output — aligning brand SVGs with this convention keeps the theme coherent end-to-end.
- SVG-swap approach (vs. `ColorFilter`) preserves the baked-in text colors in the wordmark SVGs (`#F2F1F3` near-white in dark mode) — a single color filter cannot handle a multi-color SVG correctly.

**Scope:**
- In-app widgets only: `MeridianWordmark` (`.horizontal`, `.stacked` constructors) and new `MeridianIcon`.
- Native splash: `flutter_native_splash` dark PNG variants added for Android pre-12 and Android 12+, and iOS.
- Launcher icons NOT affected — Android Material You and iOS home screen theming are managed by the OS.
- Mono wordmark constructors (`.horizontalMono`, `.horizontalMonoWhite`, `.stackedMono`) unchanged — explicit, non-adaptive by design.

**Alternatives considered:**
- `ColorFilter.mode(Colors.white, BlendMode.srcIn)` applied to primary SVG — rejected; tints entire SVG to solid white, destroying text fill distinction.
- Single SVG with CSS media query — rejected; `flutter_svg` does not evaluate CSS `prefers-color-scheme`.

---

## ADR-042: Onboarding Uses Canonical Settings Provider

**Date:** 2026-04-19
**Status:** Accepted

### Context
The original onboarding flow batched all field writes into a single `_markCompleteAndNavigate()` call at the end, writing directly to `SharedPreferences` rather than through `StationSettingsService`. This meant several fields (symbol, comment, location) were never written by onboarding, and passcode was only consumed at app startup from raw prefs rather than through the service.

### Decision
All onboarding fields are committed immediately on page advance via `StationSettingsService` setters. Onboarding maintains no separate state bag. `passcode` and `isLicensed` are added to `StationSettingsService` so it is the single source of truth for all station identity fields.

### Consequences
- No divergence between onboarding write paths and Settings read paths
- Each step's data survives a force-quit (partial completion doesn't lose data)
- `StationSettingsService` owns passcode as plaintext stopgap; v0.13 migrates to secure storage

---

## ADR-043: Single-Flag Completion Model

**Date:** 2026-04-19
**Status:** Accepted

### Context
A multi-step onboarding flow could track partial progress (which steps completed) to allow resuming mid-flow.

### Decision
Use a single `onboarding_complete` boolean in SharedPreferences. Mid-flow app close does not set the flag; relaunch starts from Welcome. No partial-progress resume.

### Consequences
Simpler implementation. Users who close mid-flow re-enter from the beginning, which is acceptable since each step's data is already committed to StationSettingsService.

---

## ADR-044: isLicensed as Primary Branching Point

**Date:** 2026-04-19
**Status:** Accepted

### Context
APRS transmitting requires an amateur radio license. The app needs to know whether the user is licensed to enable TX features.

### Decision
`StationSettingsService.isLicensed` (prefs key `user_is_licensed`, default false) is the single source of truth. TxService hard-rejects all sends when unlicensed. The onboarding License step sets this flag. No separate LicenseService class needed at this stage.

### Consequences
TX is safely blocked by default for new installs. The "I got my license" transition flow (update isLicensed in Settings, re-enable TX) is a FUTURE_FEATURES item.

---

## ADR-045: Silent N0CALL/-1 for Unlicensed APRS-IS

**Date:** 2026-04-19
**Status:** Accepted

### Context
Unlicensed users can still receive APRS packets via APRS-IS. They need to connect but should not transmit or authenticate as a licensed station.

### Decision
When `isLicensed == false`, AprsIsConnection constructs the APRS-IS login line with callsign `N0CALL` and passcode `-1`. This is the standard APRS-IS convention for receive-only / unvalidated connections. No UI indication is shown to the user (silent).

### Consequences
Unlicensed users can receive traffic. The server-side enforcement of passcode -1 prevents them from injecting packets even if TxService's local reject were bypassed.

---

### ADR-046: APRS tocall allocation and device ID database integration

**Date:** 2026-04-19
**Status:** Accepted

**Decision:** Tocall `APMDN?` allocated by Hessu OH7LZB via the aprs-deviceid registry (2026-04-19). Version-tied wildcard convention: `APMDN0` = v0.x, `APMDN1` = v1.x, `APMDNN` = vN.x thereafter. `APMDNZ` reserved for dev/nightly build identification (not implemented; deferred until signed-release detection is wired up). Position packets use `=` DTI (messaging-capable, no timestamp) unconditionally — the `hasMessaging` parameter is removed from `AprsEncoder.encodePosition()` since Meridian always supports messaging. The `hasMessaging` field on `PositionPacket` (parsed inbound) is retained.

The APRS Foundation device-ID database (`tocalls.dense.json`, CC BY-SA 2.0) is bundled at `assets/aprs-deviceid/tocalls.dense.json` and loaded at startup via `DeviceResolver.loadFromJson()`. The lookup is wildcard-aware (longest-specificity match). The database is refreshed weekly via a GitHub Actions workflow that opens a PR when the file changes. Release tag builds fail CI if the snapshot is older than 30 days.

**Rationale:** Version-tied wildcard gives broad-strokes lineage visible on aprs.fi without burning the wildcard on platform info (Flutter is a unified cross-platform codebase). Reserved `Z` prevents dev/nightly packets from contaminating release version statistics. The bundled-JSON approach keeps the core pure Dart and avoids runtime network calls for device identification.

**Registry entry:** vendor Eric Pasch KM4TJO, model Meridian APRS, contact meridian@pasch.dev.

**Attribution:** CC BY-SA 2.0 — Heikki Hannikainen OH7LZB and contributors. Displayed in About screen and README.

---

## ADR-047: SecureCredentialStore abstraction (v0.13)

**Date:** 2026-04-21
**Status:** Accepted

### Context

The APRS-IS passcode was stored in `SharedPreferences` under the key `user_passcode`. SharedPreferences is plaintext on all platforms — the passcode (a derived number from the licensed callsign, not a high-entropy secret) was recoverable from an adb backup or standard file system inspection. While the threat model for APRS passcodes is low, storing credentials in plaintext is poor hygiene and fails basic app-store security review expectations.

### Decision

Introduce `SecureCredentialStore` (`lib/core/credentials/`) as an abstract interface backed by `flutter_secure_storage`:

- **Interface contract:** `read(CredentialKey)` → `String?`, `write(CredentialKey, String)`, `delete(CredentialKey)`, `exists(CredentialKey)` → `bool`, `clear()`. Missing credentials return `null`; platform failures throw `CredentialStoreException`.
- **`CredentialKey`** is a sealed class with a single member `aprsIsPasscode`. No placeholder keys — keys are added only when a real credential is needed.
- **Platform backends** (via `flutter_secure_storage ^9.2.2`): Android `EncryptedSharedPreferences`, iOS/macOS Keychain, Windows Credential Manager, Linux `libsecret`, web encrypted IndexedDB.
- **Web caveat:** Web credential storage depends on browser implementation of the Web Crypto API and is not backed by a hardware element. This is documented in the About screen and README.
- The `FlutterSecureCredentialStore` concrete implementation is the production backend. A `FakeSecureCredentialStore` backed by an in-memory `Map` supports unit tests without platform channels.

### Consequences

Passcode is no longer stored in plaintext SharedPreferences. No migration code — v0.13 drops `_keyPasscode` from `StationSettingsService` entirely; existing passcode values in SharedPreferences are orphaned silently (users re-enter their passcode once after upgrade, which is acceptable). Background isolate (`MeridianConnectionTask`) reads the passcode via `flutter_secure_storage` directly — the package supports background isolates on Android and iOS.

---

## ADR-048: ConnectionCredentials value object (v0.13)

**Date:** 2026-04-21
**Status:** Accepted

### Context

`AprsIsConnection` (Connection Core, `lib/core/connection/`) previously imported `StationSettingsService` (Service Layer) to read callsign, SSID, passcode, and `isLicensed`. This is an upward layer violation: Core should not depend on Service.

### Decision

Introduce `ConnectionCredentials { String callsign; int ssid; String passcode; bool isLicensed; }` in `lib/core/connection/connection_credentials.dart`. `StationSettingsService` exposes a `credentials` getter that constructs the value object. `AprsIsConnection` accepts `ConnectionCredentials` at construction time and via `updateCredentials(ConnectionCredentials)` — no longer imports `StationSettingsService`.

`aprsIsLoginLine` and `isLicensed` are derived from `ConnectionCredentials` internally. The N0CALL/-1 unlicensed override (ADR-045) is applied inside `AprsIsConnection._applyLicenseOverride()`.

### Consequences

`AprsIsConnection` is now a pure Connection Core class. The only upward dependency removed is `StationSettingsService`; transport and packet core imports remain appropriate. `main.dart` passes the initial credentials at construction and subscribes to `StationSettingsService` changes to call `updateCredentials`.

---

## ADR-049: LatLngBox replaces LatLngBounds in Connection Core (v0.13)

**Date:** 2026-04-21
**Status:** Accepted

### Context

`AprsIsConnection.updateFilter(LatLngBounds)` imported `LatLngBounds` from the `flutter_map` package — a UI-layer library — directly into the Connection Core. This is the same upward layer violation as ADR-048 but for the filter-update path.

### Decision

Introduce `LatLngBox { double north; double west; double south; double east; }` in `lib/core/connection/lat_lng_box.dart`. The `updateFilter` signature becomes `updateFilter(LatLngBox)`. The conversion from `flutter_map`'s `LatLngBounds` to `LatLngBox` happens at the UI boundary in `map_screen.dart`.

### Consequences

`flutter_map` is no longer imported by any file in `lib/core/`. The Connection Core is now isolated from UI-layer dependencies. `LatLngBox` is a simple value class with no external dependencies.

---

## ADR-050: AprsIsFilterConfig preset model (v0.13)

**Date:** 2026-04-21
**Status:** Accepted

### Context

v0.13 introduces user-configurable APRS-IS server-side filter presets. The filter is expressed as a bounding-box (`b/`) string derived from the map viewport. Three parameters describe the filter shape: the viewport pad fraction, and a minimum radius floor.

A third parameter, station time window (minutes), was considered but rejected: the APRS-IS `b/` filter is a purely geographic gate — it has no time dimension. Implementing a time window here would require polling the connection for periodic filter rotation, which adds complexity for no server-side benefit. Station-age filtering is already handled client-side in `StationService` via the time filter introduced in v0.10.

### Decision

`AprsIsFilterConfig` stores three fields: `preset` (`AprsIsFilterPreset { local, regional, wide, custom }`), `padPct` (viewport pad fraction), `minRadiusKm` (minimum bounding-box half-size in km). No `stationWindow` field.

Preset snap table:

| Preset | padPct | minRadiusKm |
|---|---|---|
| local | 0.10 | 25 km |
| regional (default) | 0.25 | 50 km |
| wide | 0.50 | 150 km |
| custom | user-set | user-set |

The `custom` preset is entered automatically when the user adjusts either slider away from the active preset's values. Custom values persist independently of preset values (separate SharedPreferences keys). Changing back to a named preset snaps values; returning to `custom` restores the previously edited custom values.

`AprsIsFilterConfig` is owned by `StationSettingsService` and persisted to SharedPreferences. `AprsIsConnection.updateFilter` reads the config through the existing viewport-update path — no reconnect needed.

### Consequences

No stationWindow means one less SharedPreferences key, one less slider in the UI, and no reconnection-on-window-change complexity. The client-side time filter in `StationService` already covers the station-age use case. The preset UI (four-option `SegmentedButton` + collapsible Advanced sliders) lives in `lib/screens/settings/sections/aprs_is_filter_section.dart`.

---

## ADR-051: TxTransportPref full removal (v0.13, ADR-029 follow-up)

**Date:** 2026-04-21
**Status:** Accepted

### Context

ADR-029 established the `ConnectionRegistry` abstraction with an unconditional Serial > BLE > APRS-IS routing hierarchy. However, `TxService` retained a `TxTransportPref { auto, aprsIs, tnc }` enum that allowed per-session and per-message transport overrides. This surface was incompatible with ADR-029's hierarchy model and added state that had to be tracked, persisted, and tested. v0.13 includes audit finding F-ARCH-002 (#48) calling for its removal.

### Decision

`TxTransportPref` enum and all associated surfaces are removed from `TxService`:
- Removed fields: `_preference`, `_userHasExplicitlySet`, `_tncWasConnected` context.
- Removed public API: `preference`, `userHasExplicitlySet`, `effective`, `aprsIsAvailable`, `tncAvailable`, `beaconToAprsIs`, `beaconToTnc`, `setBeaconToAprsIs`, `setBeaconToTnc`, `setPreference`, `loadPersistedPreference`.
- `MessageThreadScreen` loses the per-message IS/RF `SegmentedButton` — all sends follow the unconditional hierarchy.
- `MeridianConnectionTask` background isolate migrates from legacy `beacon_to_aprs_is` / `beacon_to_tnc` global pref keys to per-connection `beacon_enabled_<id>` keys (already written by `ConnectionRegistry.loadAllSettings`).
- Legacy SharedPreferences keys `beacon_to_aprs_is`, `beacon_to_tnc` are orphaned — no migration (consistent with no-migration policy for this milestone).
- `main.dart` no longer calls `txService.loadPersistedPreference()`.

`TxService` retains: `resolvedTxLabel`, `sendLine`, `sendBeacon`, `sendViaTncOnly`, `events` stream, `TxEventTncDisconnected`, `TxEventTncReconnected`.

### Consequences

Simpler `TxService` with no persisted routing state. Routing is always hierarchy-driven. The TNC-disconnect banner in `MapScreen` now only reports the disconnect event and the fallback transport — it no longer offers a "switch to APRS-IS" action because that is now the automatic behavior. Users lose the per-message IS/RF override in `MessageThreadScreen`, which is an acceptable tradeoff given the explicit ADR-029 hierarchy commitment.

---

## ADR-052: foregroundServiceType connectedDevice addition (v0.13, ADR-025 follow-up)

**Date:** 2026-04-21
**Status:** Superseded by ADR-060 (2026-04-24) — the runtime-permission analysis below was incorrect; `connectedDevice` crashes targetSdk 34+ APRS-IS sessions when Bluetooth is not granted at runtime.

### Context

ADR-025 established the Android foreground service for background APRS connectivity. The service uses `foregroundServiceType="dataSync|location"` to satisfy Android API 34 requirements for foreground services with data sync and location access. However, the service also maintains a BLE TNC connection alive — on Android 14+ (API 34), a foreground service that manages a connected Bluetooth device must declare `connectedDevice` in `foregroundServiceType` and hold the `FOREGROUND_SERVICE_CONNECTED_DEVICE` permission. This was missing, creating a policy violation that would be caught on API 34+ devices.

### Decision

- `AndroidManifest.xml`: service `foregroundServiceType` updated from `"dataSync|location"` to `"dataSync|location|connectedDevice"`.
- `AndroidManifest.xml`: `FOREGROUND_SERVICE_CONNECTED_DEVICE` permission added with `android:minSdkVersion="34"`.

This resolves audit finding F-META-003 (#44). ADR-025's narrative is updated to reflect all three service types.

### Consequences

No runtime behavior change on Android < 14. On Android 14+, the foreground service now correctly declares all its capabilities to the OS. Google Play policy compliance is maintained. The `connectedDevice` type declaration does not require an additional runtime permission prompt — it is a manifest-level declaration only.

## ADR-053: Settings screen reorganization — IA, master/detail, Advanced User Mode

**Date:** 2026-04-22
**Status:** Accepted

### Context

The Settings screen was a monolithic `ListView` with 13 sections stacked vertically, three of which were placeholder stubs. There was no category navigation, no responsive layout, and several controls used inappropriate widget types (switches for unit selectors, free-form sliders for discrete choices, cramped trailing dropdowns for retention settings).

### Decision

- **Information architecture**: 8 top-level categories (My Station, Beaconing, Connections, Map, Notifications, History & Storage, Appearance, About), each with its own content screen. Three stub sections (DisplaySection, AccountSection, ConnectionSection) deleted. About + Acknowledgements and Appearance + App Color merged.
- **Responsive layout**: `LayoutBuilder` at the settings root; ≥840dp → master/detail two-pane (280dp fixed left pane + expanded detail); <840dp → hierarchical push-nav via `buildPlatformRoute`. Breakpoint aligns with the MD3 medium compact boundary.
- **Advanced User Mode**: New `AdvancedModeController extends ChangeNotifier`, backed by SharedPreferences key `advanced_user_mode_enabled` (default false). Follows the `ThemeController` async factory pattern. Wired into `MultiProvider` in `main.dart`. Advanced toggle sits above the category list. When off, advanced-gated settings are hidden but stored values are preserved.
- **Advanced-gated settings**: SmartBeaconing™ Parameters tile (Beaconing), APRS-IS filter Custom preset + sliders (Connections), APRS-IS server override (Connections), WX overlay search radius / temp units / data max age (Map), Clear packet log + Clear stations (History).
- **Control-type changes**: Distance units and temperature units → `SegmentedButton`/`CupertinoSlidingSegmentedControl`; Beacon Interval → discrete 8-stop slider [1,2,5,10,15,20,30,60 min]; Station Timeout → `SwitchListTile.adaptive` + dialog picker; History retention → dialog picker (Material `SimpleDialog` / iOS `CupertinoActionSheet`); APRS-IS filter sliders moved inline (ExpansionTile removed).
- **APRS-IS server override**: New SharedPreferences key `aprs_is_server_override` (String, optional). `AprsIsTransport.host`/`port` made mutable with `updateServer()`. `AprsIsConnection.setServerOverride(String?)` parses and applies the override; reads it in `loadPersistedSettings()`. Setting takes effect on next connection; a snackbar informs the user if currently connected.

### Consequences

Settings categories are individually navigable. Desktop users get a persistent master/detail view. Advanced users can expose power-user controls. All existing SharedPreferences keys are preserved — no migration needed. The `sections/` subdirectory is fully removed; content lives in `category/`.

---

## ADR-054: Base-callsign message matching — capture-always with filter-on-display (v0.14)

**Date:** 2026-04-22
**Status:** Accepted

### Context

APRS operators frequently run multiple stations under one base callsign (e.g., `-7` HT, `-9` mobile, `-5` home). Per spec, a message to `KM4TJO-7` is only for that station — but the human operator often wants visibility into messages addressed to "any version of me." APRSDroid handles this by matching on base callsign by default; Meridian offers it as a user-controlled feature with explicit UX around the mismatch.

### Decision

1. **Capture-always.** All messages addressed to any SSID of the operator's base callsign are ingested and persisted regardless of user preferences. Two independent preferences (`showOtherSsids`, `notifyOtherSsids`) act as pure UI filters over the captured set — they never gate ingestion. Benefits: toggling is instant and non-destructive; historical messages surface on toggle-on without data loss; future features (missed-while-away views) require no re-architecture. APRS message payloads are ≤67 bytes, so storage overhead is negligible.

2. **Asymmetric matching.** Base-callsign matching applies only to the operator's own identity. The other party's SSIDs remain strictly separate threads. Rationale: (a) I know my own SSIDs are one human; I don't know that about theirs. (b) SSIDs encode network role — merging their side creates "reply to whom?" ambiguity with no safe default. (c) Reply routing stays unambiguous: replies always go to the exact sender of the specific message being replied to.

3. **ACK strictness is a correctness requirement.** ACKs are sent only on exact-match addressee (with SSID `-0` normalized to no-SSID per APRS spec). Cross-SSID received messages never generate an ACK. Dual-ACKs corrupt the sender's message-ID tracking. This is non-negotiable regardless of display preferences.

4. **`-0` normalization.** Per APRS spec, SSID `-0` and no SSID designate the same station. `normalizeCallsign()` strips the `-0` suffix before equality checks. `stripSsid()` returns the base callsign for all SSID forms (numeric 0–15, D-STAR letter A–Z, no suffix).

5. **Conversation grouping is a presentation layer.** Threads sharing a base callsign are visually grouped in the conversation list when 2+ threads exist (single threads render flat — no visual noise). Grouping does not merge data, reply targets, or notifications. Group headers are designed to accept a contact-name override when a contacts feature is added.

6. **`addressee` stored on incoming `MessageEntry`.** Null for outgoing messages. `isCrossSsid(myFullAddress)` derived at read time. Legacy serialized entries (no `addressee` key) deserialize as null and render as exact-match — safe backward compat. If the operator changes their own callsign, historical cross-SSID flags recompute at read time (acceptable; callsign changes are rare).

7. **Notification copy differentiates match type.** Exact match: `W1ABC-9: <body>`. Cross-SSID: `W1ABC-9 → your -7: <body>`. Makes the mismatch explicit without being alarming. Android reply routing uses the sender's exact callsign unchanged.

### Consequences

- New `lib/core/callsign/callsign_utils.dart` with `stripSsid` / `normalizeCallsign`. Inline `split('-')` patterns in `ble_connection_impl.dart` and `serial_connection_impl.dart` are candidates for future consolidation (out of scope v0.14).
- `MessageEntry.addressee` field added; existing serialized entries get `null` → backward compat.
- `MessageService.showOtherSsids` (SharedPreferences key `msg_show_other_ssids`) gates the `conversations` getter.
- `MessageService.allConversations` exposes the unfiltered list for `NotificationService`.
- `NotificationPreferences.notifyOtherSsids` (key `notif_notify_other_ssids`) gates cross-SSID system notifications.
- New Settings → Messaging category (`lib/screens/settings/category/messaging_screen.dart`).
- Spec: `docs/specs/base-callsign-message-matching.md`

---

## ADR-055: Addressee matcher precedence — Bulletin → Direct → Group (v0.17)

**Date:** 2026-04-23
**Status:** Accepted

### Context

v0.17 adds two new APRS message categories (group messages, bulletins) alongside the existing direct path from v0.5 and base-callsign matching from v0.14 (ADR-054). Every incoming `MessagePacket` must be classified into exactly one of {Direct, Group, Bulletin, None} before storage, display, or ACK generation. The classification determines whether an ACK is sent.

The ordering of the classification rules is load-bearing — a seemingly cosmetic refactor (collapsing them into a single matcher list, or reordering for "clarity") can silently break ACK correctness in ways that don't surface until a user in a specific configuration experiences an "unreachable" operator.

### Decision

The addressee matcher applies three rules in a **fixed first-match-wins order**:

1. **Bulletin** — addressee matches `^BLN[0-9A-Z]`
2. **Direct** — addressee matches the operator's own callsign per ADR-054 (exact or cross-SSID)
3. **Group** — addressee matches any enabled `GroupSubscription` per its `matchMode`

Implementation details that are part of the contract:

- The classifier function is named `classifyWithPrecedence()` — not `classify()` or a generic matcher loop. The name signals intent and surfaces the ordering rule at every call site.
- A doc comment on the method states the rule and references this ADR. The library-level doc comment on `lib/core/callsign/addressee_matcher.dart` includes a "do not reorder / do not rename / do not collapse" warning.
- The sealed `MessageClassification` type (`BulletinClassification` | `DirectClassification` | `GroupClassification` | `NoneClassification`) forces handlers to switch on the concrete variant — there is no boolean "isBulletin" that could be mishandled in isolation.
- `DirectClassification` carries `isExactMatch` so the downstream ACK gate (exact match only, per ADR-054) is preserved.
- Group precedence within rule 3 is first-subscription-wins in user-defined order, so the Settings "reorder" UX maps directly to matcher behavior.

### Why this exact order

- **Bulletin first.** Syntactically unambiguous — no legitimate callsign starts with `BLN[0-9A-Z]`. Prevents pathological groups (e.g., user creates a group named `B` with prefix match) from capturing bulletins.
- **Direct before Group.** Guarantees messages addressed to the operator's own callsign classify as direct and get ACKed when exact. If Group came first, a permissive custom group (e.g., `W1` with prefix match when operator is `W1ABC`) would capture direct messages to `W1ABC-7`, skip the ACK, and the sender's retry loop would never terminate — the operator would appear unreachable despite receiving. This is a silent protocol violation with no obvious log signature.
- **Group last.** User-configurable and potentially broad. More specific rules are handled first; group is the fallback for addressees that aren't bulletins and aren't for me.

### Required test cases

The following table is copied into `test/core/callsign/addressee_matcher_test.dart`. These cases must pass at all times — they protect the precedence rule from silent regression.

| Case | Addressee | Setup | Expected |
|---|---|---|---|
| Bulletin beats pathological group | `BLN0` | Group `B` prefix | Bulletin |
| Bulletin beats named-overlap group | `BLN1CLUB` | Group `CLUB` | Bulletin |
| Direct beats group prefix conflict | `W1ABC-7` | Operator `W1ABC`; group `W1` prefix | Direct, ACKs |
| Direct beats group exact conflict | `W1ABC` | Operator `W1ABC`; group `W1ABC` exact | Direct, ACKs |
| Group when no direct/bulletin | `CQ` | Group `CQ` | Group, no ACK |
| First subscription wins | `CQFOO` | Groups `CQ`, `CQFOO` both prefix | First in list |
| Disabled subscriptions don't match | `CQ` | Group `CQ` disabled | None |
| Exact mode rejects longer addressee | `CQRS` | Group `CQ` exact | None |
| Prefix mode accepts longer | `CQRS` | Group `CQ` prefix | Group |

### ACK policy

| Classification | ACK? |
|---|---|
| Direct, exact match | Yes (ADR-054) |
| Direct, cross-SSID | No (ADR-054) |
| Group | Never |
| Bulletin | Never |

### If a future refactor wants to reorder these rules

**Stop.** Re-read this ADR. Reordering is a protocol correctness change, not a style change. Any PR that touches the ordering must update this ADR and justify why the required test cases above remain correct under the new order. If the cases can't be preserved, the refactor is not a refactor — it is a behavior change that needs explicit product review.

### Consequences

- New `lib/core/callsign/addressee_matcher.dart` (the classifier) + `lib/core/callsign/message_classification.dart` (sealed result type) + `lib/core/callsign/operator_identity.dart` (identity snapshot value object).
- `MessageService._onPacket` replaces its inline exact-vs-cross-SSID block with a single call to `AddresseeMatcher.classifyWithPrecedence` and switches on the sealed result.
- Existing v0.14 ACK behavior preserved: exact-match direct ACKs; cross-SSID direct does not; group and bulletin never ACK.

---

## ADR-056: Group messaging architecture (v0.17)

**Date:** 2026-04-23
**Status:** Accepted

### Context

APRS group messages (`CQ`, `ALL`, `QST`, club-defined names like `CLUB`) are a protocol-level feature inherited from Yaesu/Kenwood radios and the APRS spec §14. They are one-to-many: a sender addresses any group name and every listener whose radio is configured to match that name receives the message. There is no server-side group mechanism — "subscription" is entirely a local receiver filter.

Meridian implements the same model so it interoperates with Yaesu FT5D, Kenwood TH-D74, and modern software clients (APRSIS32, Xastir). Group messages are distinct from direct messages (different addressee shape) and distinct from bulletins (message-format DTI, ACK semantics differ).

### Decision

1. **Subscription model.** `GroupSubscription` is a local-only value object persisted to SharedPreferences. No network subscription step exists. Three protocol-neutral built-ins are seeded on first run (`ALL`, `CQ`, `QST`) — all enabled-or-not per the defaults table below. Vendor-specific group names (e.g. `YAESU`, `KENWOOD`) are intentionally *not* seeded: Meridian is not a vendor-specific product, and users who want them can add them via Settings in two taps. Users may add any custom group (club names, event nets, vendor names).

2. **Wildcards = prefix match, not regex/glob.** APRS wire addressees are 9 characters, right-space-padded. Yaesu radios emit `ALL******` as a prefix match, so the matcher trims padding and applies `addressee.startsWith(name)`. Users can opt a group into `exact` mode for strict equality (no false positives), but `prefix` is the default because it matches the ecosystem.

3. **Default reply modes are opinionated.**
   - Built-ins `ALL`, `CQ`, `QST` default to `replyMode = sender` — these are broadcast/discovery conventions where the right reply is 1:1 to whoever spoke up.
   - Custom groups default to `replyMode = group` — clubs want chat-room semantics.
   - The UI surfaces the reply-mode icon (`campaign` for sender, `forum` for group) on every group tile so the mental model is visible.

4. **ACK policy: never.** Group messages are one-to-many; per APRS convention they are not acknowledged. Even when the wire carries a message-ID suffix, the matcher never emits an ACK for a `GroupClassification`. See ADR-055 for the full matrix.

5. **Name validation: `[A-Z0-9]{1,9}`.** 9 characters is the wire addressee limit. Upper-cased on set; the settings editor normalizes input. No punctuation — the wire field is ASCII alphanumeric only.

6. **Built-ins may be disabled, not deleted or renamed.** This preserves the "quiet by default" opt-in for `ALL` while keeping the defaults discoverable. `isBuiltin: true` is set on the seeded rows and enforced by the service.

7. **First-match-wins within user-defined order.** Groups `CQ` and `CQFOO` both in prefix mode for addressee `CQFOO` → whichever appears earlier in the subscription list wins. Settings provides a reorderable list so operators can place narrow before broad when they care.

8. **Group conversations keyed in the existing `_conversations` map** under `#GROUP:<NAME>` prefix (no callsign starts with `#`, so no collision). Keeps the v0.14 persistence layer intact — no separate storage schema for PR 1. v0.15's drift migration will consolidate both direct and group threads into the same message table.

9. **Own-SSID echo.** When the user sends a group message, the service also captures it as a received group message from the operator's own callsign — so it appears in the group channel view alongside replies. This is receive-side behavior only; send wiring completes in PR 4.

### Consequences

- New `lib/models/group_subscription.dart` — `GroupSubscription`, `MatchMode`, `ReplyMode`, `matches()` helper.
- New `lib/services/group_subscription_service.dart` — CRUD + seeder (`group_subscriptions_v1` SharedPreferences key, `group_subscriptions_seeded_v1` idempotence flag).
- `MessageEntry.category: MessageCategory` + `MessageEntry.groupName: String?` — legacy-safe JSON deserialization (missing keys default to `direct` + null).
- `MessageCategory` enum in `lib/models/message_category.dart`.
- Send path, adaptive compose, group channel view, reply-mode routing — PR 3 / PR 4 of v0.17.

---

## ADR-057: Bulletin transmission model — APRSIS32 fixed interval (v0.17)

**Date:** 2026-04-23 (proposed) / 2026-04-24 (accepted, PR 4)
**Status:** Accepted

### Context

Two APRS bulletin transmission conventions exist in the wild:

1. **WB4APR exponential decay** — send at 1m, 2m, 4m, 8m, …, up to some cap. Reduces channel load over time. Originally designed for AX.25 RF bulletin boards where bulletins lived for days.
2. **APRSIS32 fixed-interval** — send at a user-chosen interval (typically 30 min) for a bounded lifetime (typically 24h). Simpler mental model, easier UX, matches what modern mobile-first APRS clients do.

### Decision

Use the APRSIS32 fixed-interval model with an initial pulse and a hard expiry:

- `intervalSeconds` — 0 (one-shot) or 300 / 600 / 900 / 1800 / 3600
- `expiresAt` — defaults to `createdAt + 24h`; user picks 2h / 6h / 12h / 24h / 48h
- Scheduler fires an initial pulse on creation, then retransmits every `intervalSeconds` until expiry
- Expired bulletins are disabled and fire a "repost?" notification
- Edit body or addressee → reset `lastTransmittedAt = null`, `transmissionCount = 0`; initial pulse on next tick
- Edit interval or expiry only → no reset
- Retransmission history stored as aggregate counters (`transmissionCount`, `lastTransmittedAt`) — no per-receipt array (sufficient for aging + UI, scales to the drift migration without data loss).

### Rationale

- Operators do not need minute-level tuning of channel-load; the fixed interval is well-understood.
- A bounded lifetime forces the operator to consciously re-post rather than letting stale bulletins linger.
- The decay curve in WB4APR's model assumes a low-activity mailbox paradigm that doesn't match how modern clients consume bulletins (scrolling feed + notifications).
- Fixed interval is easier to schedule in a background isolate alongside the beacon timer without dynamic recomputation.

### ACK policy

Bulletins are never ACKed. The `BulletinClassification` path in `MessageService` does not call `_transmitAck` under any circumstance.

### Consequences (realized in PR 4)

- `lib/services/bulletin_scheduler.dart` — main-isolate 30s tick, sibling to `BeaconingService`. Injectable clock for `FakeAsync`-driven tests. Emits `BulletinExpiredEvent` / `BulletinTransmittedEvent` on its `events` stream.
- `lib/services/meridian_connection_task.dart` — background-isolate bulletin timer fires the same tick logic. APRS-IS transmission uses the existing short-lived TCP helper; RF transmission forwards a `send_tnc_bulletin` IPC message to the main-isolate `BackgroundServiceManager`, which calls `TxService.sendViaTncOnly` with the Advanced-mode "Bulletin path". Background-isolate writes updates `outgoing_bulletins_v1` prefs directly; main-isolate in-memory state is resynced on next create/edit/delete (PR 5 may add AppLifecycle-resume hook for tighter sync).
- `AprsEncoder.encodeBulletin(addressee, body)` — 9-char space-padded addressee, `:BLN0     :Body`, no wire ID. Companion `encodeGroupMessage(groupName, body)` follows the same pattern for group sends.
- `MeridianConnection.sendLine(aprsLine, {digipeaterPath})` — extended with optional `digipeaterPath` so BLE/Serial connections can override the default `WIDE1-1,WIDE2-1` aliases when sending bulletins (default `WIDE2-2`) or group messages (default "same as beacon path"). APRS-IS connections ignore the parameter.
- `TxService.sendBulletin(line, {viaRf, viaAprsIs, rfPath})` — per-bulletin fan-out helper that respects the independent transport flags (unlike `sendLine`'s unconditional Serial > BLE > APRS-IS hierarchy from ADR-029).
- `BulletinService` gains `OutgoingBulletin` CRUD: `createOutgoing`, `updateOutgoingContent` (resets state), `updateOutgoingSchedule` (preserves state), `setOutgoingEnabled`, `deleteOutgoing`, `recordOutgoingTransmission`. Addressee validation via `_bulletinAddresseePattern`.
- Bulletin compose screen (`lib/screens/bulletin_compose_screen.dart`) — single-page form with type / line / group / body / interval / expiry / transport flags. Shared by create + edit.
- "My bulletins" filter on `BulletinsTab` now renders `OutgoingBulletin` rows with next-tx countdown, transmission count, per-row enable toggle, Edit, and Delete (with confirm dialog).

### Known limitations (addressed in later work)

- Main-isolate `BulletinService`'s in-memory `_outgoing` map does not auto-refresh from prefs when the background isolate mutates state during background phase. On app resume the UI may briefly show stale `lastTransmittedAt`/`transmissionCount` until the next create/edit/delete triggers a re-render. A full resume-sync hook is deferred to the v0.15 drift/SQLite migration or a follow-up hotfix.
- The background-isolate bulletin timer runs unconditionally whenever the foreground service is alive (vs. beacon timer which requires `start_beaconing` IPC). This is intentional: bulletins are independently scheduled per row, and the foreground service is only alive when the user has explicitly opted into background activity.

---

## ADR-060: Revert `connectedDevice` foreground service type (supersedes ADR-052)

**Date:** 2026-04-24
**Status:** Accepted

### Context

ADR-052 added `connectedDevice` to the Android foreground service type mask and declared the `FOREGROUND_SERVICE_CONNECTED_DEVICE` permission, reasoning that the BLE TNC keepalive qualified as managing a connected Bluetooth peripheral. The stated consequence — "does not require an additional runtime permission prompt — it is a manifest-level declaration only" — was wrong.

On `targetSdk >= 34` (Android 14+), `startForeground()` validates the type mask against *runtime-granted* permissions at dispatch time. Using `connectedDevice` requires one of `BLUETOOTH_CONNECT`, `BLUETOOTH_SCAN`, `BLUETOOTH_ADVERTISE`, or a USB permission to be granted at runtime. When a user connects only to APRS-IS (no BLE), no Bluetooth runtime grant has occurred and the type validation fails:

```
java.lang.SecurityException: Starting FGS with type connectedDevice ...
targetSDK=36 requires permissions: all of [FOREGROUND_SERVICE_CONNECTED_DEVICE]
and any of [BLUETOOTH_CONNECT, BLUETOOTH_SCAN, ...]
```

This crashes the process the moment the foreground service tries to start. Reproducible every time on a fresh install that connects to APRS-IS first.

### Decision

Drop `connectedDevice` from the declared FGS type mask. Remove the `FOREGROUND_SERVICE_CONNECTED_DEVICE` uses-permission entry. The service now declares `foregroundServiceType="dataSync|location"` only.

Rationale:
- `dataSync` legally covers the BLE TNC background session. From the OS's perspective, a TNC keepalive is an ongoing data exchange (APRS packets flowing in and out) — which is the definition of `dataSync`. `connectedDevice` is conventionally reserved for apps that actively *manage* a peripheral (car audio, fitness device sync with discovery), not for apps that merely use one as a data source.
- `FlutterForegroundTask` uses a single manifest-declared type mask for all service starts; there is no dynamic per-connection type selection. Declaring `connectedDevice` therefore gates *every* service start — including APRS-IS-only flows where Bluetooth is never used — on a runtime Bluetooth grant that may never come.
- If a future need for `connectedDevice` arises (e.g., stricter Play policy enforcement around BLE peripheral management), it must be introduced together with a dynamic-type plugin path that only adds `connectedDevice` when BLE permission is granted and a BLE connection is active. That work is out of scope here.

### Consequences

- Android 14+ APRS-IS connection flow no longer crashes on a user without BLE permission.
- BLE TNC background sessions continue to function — they rode under `dataSync` before ADR-052 and still do now.
- ADR-052 is superseded. Audit finding F-META-003 (#44) is reopened for the underlying concern (is `dataSync` semantically correct for BLE TNC?) but the crash is resolved.
- Manifest comment references this ADR so future contributors don't re-add `connectedDevice` without the dynamic plugin path.

---

## ADR-059: Messaging tab restructure — segmented Direct / Groups / Bulletins (v0.17)

**Date:** 2026-04-24
**Status:** Accepted

### Context

v0.17 adds two new top-level message surfaces (Groups and Bulletins) alongside the existing Direct thread list. All three share the same conceptual home — the "Messages" destination — but they diverge on UX semantics: Direct is 1:1 with ACK chrome, Groups is a broadcast chat room with reply-mode adaptation, Bulletins is a read-only feed with age-out. We needed to decide how the user switches between them.

Options considered:

1. **New top-level bottom-nav destinations.** Adds two icons to the mobile scaffold. Rejected — the bottom nav already holds Map / Packets / Messages / Connection / Settings, and adding two more crowds it past the Material-recommended limit (5) and would require a second "More" sheet on smaller devices.
2. **Separate subscreens pushed from Direct.** User enters Messages → taps a button → lands on Groups. Rejected — makes Groups and Bulletins feel like subordinate features rather than peers, and the back-button gesture would become the primary "switch tab" affordance.
3. **Segmented control at the top of the Messages screen.** Three peers, platform-adaptive, one tap to switch. Accepted.

### Decision

- **Segmented control** at the top of `MessagesScreen` with three values: Direct / Groups / Bulletins. Direct is the default.
- **Platform adaptivity:** Material 3 `SegmentedButton` on Android + desktop; `CupertinoSlidingSegmentedControl` on iOS. Both are platform-native idioms for 3-option toggles.
- **Unread badges** on the Direct and Groups segments (Material side only — Cupertino's sliding control doesn't support per-segment trailing content; iOS users see unread counts in the tab content itself).
- **Compose FAB** is gated to the Direct tab. Group send UI lives on the Group channel screen; Bulletin compose gets its own FAB on the Bulletins tab in PR 4.
- **Direct tab preserves v0.14 behavior byte-for-byte.** The existing conversation-grouping logic, ACK retry surface, cross-SSID filter, and compose sheet are all unchanged — only the ambient chrome (segmented control) is new.
- **Groups tab** lists `GroupSubscription` entries in user-defined order (matcher-semantics mirror: first match wins). Tapping a tile opens `GroupChannelScreen`. Empty state routes the user to Settings → Messaging → Groups.
- **Group channel screen** is a separate screen (not a reuse of `MessageThreadScreen`) because the bubble shape (sender callsign on every message), the absence of ACK/retry chrome, and the adaptive compose bar differ materially from direct threads.
- **Bulletins tab** is a flat feed with filter chips (All / General / Groups / My bulletins) and a location-unknown banner. Tapping a row opens `BulletinDetailScreen`, which is explicitly read-only — no compose affordance.

### Why a separate `GroupChannelScreen` instead of reusing `MessageThreadScreen`

- The group channel renders sender attribution on every bubble (`MessageEntry.fromCallsign`), while direct threads rely on "all messages in this thread are from the peer" and never need per-message sender labels.
- Direct threads carry ACK/retry status indicators on outgoing bubbles. Group messages have no ACK chrome (ADR-055 forbids ACKing groups), so the same bubble widget would need a toggle to suppress status — unneeded complexity.
- Direct compose is a single text field + send. Group compose must adapt to `replyMode` (sender vs. group) with a secondary action in sender mode. The compose bar branch point is non-trivial.
- Reuse would force both screens to carry the other's edge cases in its codepaths. Separate screens are cleaner and independently testable.

### Data-model addition: `MessageEntry.fromCallsign`

Group conversations are keyed by `#GROUP:<NAME>`, so the sender cannot be recovered from the parent `Conversation.peerCallsign`. We added `fromCallsign: String?` to `MessageEntry`, populated by both the direct and group incoming handlers. Null for outgoing entries and for v0.14-era legacy-deserialized entries — direct threads can still infer sender from the parent conversation key when `fromCallsign` is null.

### `allConversations` scope change

`MessageService.allConversations` now excludes group threads. Callers that need them use the new `groupConversations` accessor. The only existing caller of `allConversations` is `NotificationService`, which was designed for direct-message dispatch and should not accidentally fan out notifications to group threads (group notification dispatch lands in PR 5 via its own pipeline). The test suite was updated in lockstep.

### Consequences

- New screens: `lib/screens/group_channel_screen.dart`, `lib/screens/groups_tab.dart`, `lib/screens/bulletins_tab.dart`, `lib/screens/bulletin_detail_screen.dart`.
- `lib/screens/messages_screen.dart` rewritten from `StatelessWidget` to `StatefulWidget` with a `_tab` field; the Direct body path is lifted out unchanged.
- `MessageService` gains `groupConversations`, `groupNameOf`, `conversationForGroup`, `totalGroupUnread` and the `fromCallsign` field on `MessageEntry`.
- Widget tests in `test/widget/messages/messages_screen_test.dart` cover segmented-control rendering, Bulletins-tab gating, location-banner visibility, and adaptive-compose states.
- Bulletin distance-filter logic and notification dispatch for groups/bulletins still live in PR 5. The PR 3 location-unknown banner implements the user-visible behavior (hide general APRS-IS bulletins when no station location is set) directly in `BulletinsTab` so the banner copy is truthful from day one.


---

## ADR-058: APRS-IS filter scope extension + client-side bulletin distance filter (v0.17 PR 5)

**Status:** Accepted
**Date:** 2026-04-24
**Context:** v0.17 PR 5 closes the receive side of the bulletin + group-message stack. The server-side APRS-IS filter previously requested only a viewport-derived area clause (`a/N/W/S/E`) — bulletins addressed to `BLN0`–`BLN9` and named-bulletin groups (`BLN*WX`, etc.) were only received when the sender happened to be inside the current viewport box. Two problems follow: general bulletins are intentionally broadcast-global so operators expect to see them regardless of viewport; and named bulletin groups are explicitly subscribed-to so the server should be asked for them by name. Simultaneously, receiving every global bulletin in the feed is noisy — operators want to scope "general" bulletins to a sensible distance around their own station.

### Decision

1. **Filter shape.** Extract `AprsIsFilterBuilder` from the inline `updateFilter` in `AprsIsConnection` and extend the emitted `#filter` line to always include `g/BLN0/BLN1/.../BLN9` as a second clause after `a/`. For each enabled `BulletinSubscription`, append a `g/BLN*NAME` wildcard clause. The builder deduplicates and uppercases named groups, and drops malformed names (>5 chars, non-alphanumeric) rather than surfacing errors up to callers.

2. **Filter rebuild trigger.** `AprsIsConnection.onSubscriptionsChanged(List<String> names)` replaces the named-group set and re-sends `#filter` using the last viewport box. `main.dart` subscribes to `BulletinSubscriptionService` and pipes change notifications into that method so the subscription set edits push through to the server within one tick.

3. **Client-side distance filter.** `BulletinService` holds an optional `_operatorLat/_operatorLon` pushed in from `StationSettingsService` (manual position) and filters general APRS-IS bulletins by haversine distance against the sender's last-known station position. **RF bulletins are never distance-filtered** (short-range already). **Named-group bulletins are never distance-filtered** (explicit subscribe = intentional). The radius uses the existing `bulletins_radius_km` pref with `-1` as the "Global" sentinel that disables the filter entirely.

4. **Conservative drop policy.** When either position is unknown the bulletin is kept — the operator sees it, and the already-existing "location unknown" banner in `BulletinsTab` prompts them to set their location. In GPS mode we do not feed the operator's GPS fix into `BulletinService` for now (circular-import risk with `BeaconingService`); GPS-mode operators effectively get a global feed until they enable manual positioning or a future PR wires the GPS push.

5. **Notification channels.** New Android notification channels register in `NotificationService._registerAndroidChannels()`:
   - `groups_builtin` — LOW importance, silent. Built-in groups (CQ, QST, ALL) default to notify OFF.
   - `groups_custom` — DEFAULT importance. Custom groups the operator added themselves default to notify ON.
   - `bulletins_general` — LOW importance, silent. General BLN0–9 bulletins default OFF.
   - `bulletins_subscribed` — DEFAULT importance. Named-bulletin-group bulletins default ON (explicit subscribe implies the operator wants them).
   - `bulletin_expired` — DEFAULT importance. "Your outgoing bulletin expired — repost?" prompts.

### Rationale

Separating built-in from custom groups lets the operator mute the broadcast-noisy built-ins without giving up their own group chatter, and keeps the per-group `notify` toggle on `GroupSubscription` meaningful. Putting the bulletin scope filter on the client rather than relying on APRS-IS server filter syntax keeps Meridian in control of the radius semantics (haversine with earthRadius=6371 km) and lets the filter stay correct when the server-side filter language inevitably ships a different edge case in a future aprsc release.

### Consequences

- New file: `lib/core/connection/aprs_is_filter_builder.dart`; `AprsIsConnection.updateFilter` now delegates to it. Pre-v0.17 filter line (no `g/` clauses) is not preserved; existing operators will see slightly more bulletin traffic on APRS-IS but no other behaviour change.
- `BulletinService` gains `setOperatorLocation({lat, lon})` and haversine math. `MessageService` resolves sender position from `StationService.currentStations[source]` before calling `ingest` so the distance check has both endpoints.
- `NotificationPreferences` gains the new channel defaults plus per-channel rows in its map; migration from pre-v0.17 state is safe because the `load` path reads with a default-per-channel fallback.
- `NotificationService` takes optional `bulletinService` + `groupSubscriptions` constructor args so existing tests can continue to construct it without the group/bulletin pipeline.
- Widget tests for filter + distance covered; notification-dispatch tests are Android/iOS platform-gated and deferred to the manual verification pass on device.

### Out of scope (deferred)

- GPS-mode operator-location push into `BulletinService`. A clean shape is for `BeaconingService` to emit `onLocationFixed(lat, lon)` and have `main.dart` fan out to `BulletinService`; filed as a v0.15 cleanup so we don't wire it hastily under the v0.17 deadline.
- Persisting the `_lastBulletinKey` snapshot across cold starts. Currently re-seeded from `BulletinService.bulletins` on `initialize()` so the first post-restart refresh doesn't spam notifications for every persisted bulletin.
- Android native `UNNotificationCategory` entries for iOS group/bulletin channels — channel registration here is the Dart-side `DarwinNotificationCategory` story; the richer action-based categories (like Messages) land when/if we add reply affordances to group threads from notifications.

---

## ADR-061: APRS-IS background RX — read-side idle watchdog + SO_KEEPALIVE + 30 s background reconnect (Issue #76)

**Date:** 2026-04-24
**Status:** Accepted
**Supersedes:** none. **Related:** ADR-030 (iOS background), ADR-032 (no background isolate on iOS), ADR-036 (notifications on main isolate), ADR-060 (FGS type mask).

### Context

After Android backgrounds the app (screen lock), the persistent APRS-IS TCP socket on the main isolate stops receiving packets even though the foreground service is alive and the background-isolate beacon path keeps egressing. On resume the server replays the filter feed and packets flood in — confirming the read side was dead but went undetected.

Two failure modes are at work:

1. The Android kernel reaps idle TCP sockets aggressively under Doze and Wi-Fi sleep, despite the FGS wake lock keeping the *process* alive.
2. `AprsIsTransport` did not detect a silently-wedged socket: it only emitted `disconnected` when the OS surfaced an explicit `onError` / `onDone`. A half-dead socket can sit indefinitely without either firing, so the existing reconnect path in `BackgroundServiceManager._maybeReconnectInBackground` never gets a chance to run.

We considered three options (per the issue body):

1. Application-layer keepalive writes (e.g. send `# meridian keepalive` every 30 s). Proactively keeps the socket warm. Costs battery (radio wake on every cadence), fights Android's Doze design intent, and risks OEM "abnormal background activity" flags on MIUI / OneUI / EMUI.
2. Move the persistent RX socket into the background isolate alongside the bulletin / beacon timers. Largest change; violates ADR-036 ("packets flow on main isolate") and forces a redesign of how `StationService` and `MessageService` subscribe.
3. Detection-based recovery — accept that the socket will sometimes die, detect dead sockets fast, reconnect cleanly. Aligns with platform design intent.

### Decision

Adopt option 3, the detection-based recovery model. Specifically:

- **Kernel SO_KEEPALIVE** on the connected socket (best-effort via `Socket.setRawOption`). The TCP stack itself sends keepalive probes; these reveal half-dead sockets at the kernel layer without us paying any application-level cost. Failure to set the option is logged and ignored — the read watchdog still covers us.
- **TCP_NODELAY** is also set (Nagle disabled) so short APRS lines flush immediately. This is incidental polish, not load-bearing for #76.
- **Read-side idle watchdog** — a 120 s `Timer` that resets on every received line. APRS-IS servers (aprsc, javAPRSSrvr) emit periodic `# server-name ...` keepalive comments roughly every 20 s, so any healthy connection produces inbound bytes well within 120 s. When the timer fires, the watchdog calls `_socket.destroy()`; the existing listener's `onError` / `onDone` path then runs through the normal disconnected-state bookkeeping and `BackgroundServiceManager` schedules a reconnect.
- **30 s background reconnect cadence** — `BackgroundServiceManager._kReconnectDelay` raised from 10 s to 30 s. At 10 s we re-attempt aggressively while Doze is throttling network access, which can put the app on the platform's "abnormal background activity" list. 30 s gives the radio time to settle. The foreground reconnect path (`AppLifecycleState.resumed`) is unaffected and still fires immediately, so user-perceived recovery latency on app return is unchanged.

We explicitly **do not** add an outbound application-layer keepalive write. The server already supplies the cadence we need to detect death; adding our own writes would only cost battery and is not justified until field data shows the read watchdog is insufficient.

### Worst-case latency

A wedged socket is recovered within ~150 s end-to-end while the app is backgrounded:

```
120 s read watchdog
+ 30 s background reconnect delay
+ ~3 s reconnect (TCP + login)
≈ 150 s
```

Compared to the old behaviour (potentially indefinite RX-dead until the user resumed the app), this is a substantial improvement and is well within the issue's acceptance criteria for screen-off RX continuity.

### Consequences

- New code in `lib/core/transport/aprs_is_transport.dart`: `_readWatchdog` timer, `_resetReadWatchdog` / `_cancelReadWatchdog` helpers, `_onReadIdleTimeout` handler, two `@visibleForTesting` debug hooks (`debugFireReadWatchdog`, `debugReadWatchdogActive`). SO_KEEPALIVE wired in `connect()`. Watchdog cancelled in `disconnect()`, `onError`, `onDone`, and on connect-failure exceptions.
- `BackgroundServiceManager._kReconnectDelay` constant changed; its docstring documents the rationale.
- New tests in `test/core/transport/aprs_is_transport_test.dart` against a localhost `ServerSocket` cover: arm on connect, cancel on disconnect, fire-handler tears down socket and emits `disconnected`, inbound line resets the timer.
- No changes to `meridian_connection_task.dart`, `AndroidManifest.xml`, or any UI-layer code.
- iOS is unaffected (different background model — see ADR-030 / ADR-032). Desktop and web are unaffected.

### Out of scope (deferred)

- An opt-in outbound keepalive setting if real-world device verification shows 120 s detection still leaves user-visible gaps. Reassess after a field test pass.
- Per-platform tuning of the SO_KEEPALIVE option number (Linux/Android `9`, macOS/iOS `8`). The current implementation tries the Linux value and silently catches; macOS / iOS users still get full coverage from the read watchdog.
- A configurable read-idle window in Settings → Advanced. 120 s was chosen to comfortably exceed the typical server keepalive cadence; surfacing it as a knob is unnecessary unless we encounter servers with materially different behaviour.


## ADR-062: Inject `Clock` typedef for deterministic time-dependent logic

**Date:** 2026-04-26
**Status:** Accepted

### Context

Three independent audits (F-ARCH-006 / F-EXT-002 / F-FLT-009) flagged `DateTime.now()` scattered across the service layer. Concretely it blocks deterministic testing of:

- `BeaconingService` interval / smart-turn / reschedule logic.
- `MessageService` retry-backoff and pruning.
- `StationService` / `BulletinService` retention pruning.
- `BackgroundServiceManager` and `MeridianConnectionTask` liveness / heartbeat / beacon-resume math.
- `SmartBeaconScheduler` interval-after-beacon and only-shorten reschedule.

It also coupled `AprsParser` to wall-clock — a parser should be a pure function of input bytes, with the received-at stamp supplied at the transport boundary.

### Decision

Introduce `typedef Clock = DateTime Function();` in `lib/core/util/clock.dart` (no external dependency).

- Each affected class accepts `Clock clock = DateTime.now` as a defaulted constructor parameter and stores it as `final Clock _clock`. Body sites call `_clock()` instead of `DateTime.now()`.
- `AprsParser.parse(...)` and `AprsParser.parseFrame(...)` now take `required DateTime receivedAt`. The parser contains zero `DateTime.now()` calls.
- `StationService` is the canonical transport-boundary stamp site: `_handleLine` calls `_parser.parse(raw, transportSource: source, receivedAt: _clock().toUtc())`. `BleConnection` and `SerialConnection` also stamp via their own injected clock when reconstructing AX.25 frame text (the timestamp is structurally required but discarded — only `packet.rawLine` is forwarded; `StationService` re-stamps on ingestion).
- `BulletinScheduler` already followed this pattern with an inline `DateTime Function()? clock` parameter; standardised on the new `Clock` typedef.

### Alternatives considered

- **`package:clock`** — rejected to keep zero-dep posture in the core. The project already had a proven in-house pattern (`BulletinScheduler._MutableClock` test helper), and the typedef is a single line of code. The package is already a *transitive* dependency via `intl`, but we deliberately do not depend on its API surface so future churn there cannot break us.
- **Per-method `DateTime? now` overrides everywhere** — rejected as too invasive at call sites and inconsistent with `BulletinScheduler`. `SmartBeaconScheduler` retains its existing per-method `now` parameter as a convenience but its fallback now reads `_clock()` instead of `DateTime.now()`.

### Consequences

- UI date/time formatters (`*_screen.dart`, `*_tab.dart`, `chat_bubble.dart`, `station_list_tile.dart`, etc.) intentionally remain on `DateTime.now()` — they want render-time "now" and are out of scope.
- Tests can fake-advance time per service via the same `_MutableClock` shape used in `bulletin_scheduler_test.dart`. Full per-service coverage is deferred to PR 4 (#60, TxService routing) and PR 5 (#52, BeaconingService).
- One spot-check test (`test/core/util/clock_injection_test.dart`) covers `StationService` retention pruning end-to-end as proof of the seam.
- Future replay / golden-frame test flows are now feasible — a recorded packet stream can be played through the parser with a deterministic timeline.
- The background isolate's `MeridianConnectionTask` accepts a `Clock` too, for unit tests; the production `vm:entry-point` constructs it with the default `DateTime.now`.

---

## ADR-063: `StationService` owns connection-line ingestion via attached `ConnectionRegistry` subscription

**Date:** 2026-04-26
**Status:** Accepted

### Context

Every `MeridianConnection.lines` stream was being subscribed to twice:

1. `ConnectionRegistry.register` subscribed per-connection and re-emitted each line as a tagged tuple onto `registry.lines` (`Stream<({String line, ConnectionType source})>`). This stream had **zero production consumers** — only two test sites touched it.
2. `main.dart` subscribed per-connection again and forwarded each line to `StationService.ingestLine(...)` with a hand-mapped `PacketSource` tag.

The result was duplicate listener machinery for every transport, dead broadcast plumbing in the registry, and a per-connection mapping helper living in `main.dart` that should have been internal to the service.

### Decision

`StationService` owns connection-line ingestion. A single subscription is established via `StationService.attach(ConnectionRegistry)` against `registry.lines`, and the `ConnectionType → PacketSource` mapping moves into the service as a private helper. `main.dart` calls `service.attach(registry)` exactly once at startup. The subscription is cancelled in `StationService.stop()`.

`ConnectionRegistry`'s broadcast plumbing is preserved unchanged and is now a real, used seam: `registry.lines` has exactly one production consumer, but the broadcast contract means future consumers (logging tap, TX confirmation observer, replay capture) can attach without touching either layer.

`StationService.ingestLine(...)` remains public unchanged — it is the synchronous direct-injection seam used by ~30 service tests and by the background-isolate packet relay (`BackgroundServiceManager.onPacketLogged`). Both `attach` and `ingestLine` ultimately route through the same `_handleLine`.

### Alternatives considered

- **Delete `registry.lines` entirely.** Rejected: the broadcast hub is a useful future seam for non-decoding consumers (logging taps, TX confirmation observers, future replay capture), and broadcast streams have zero cost when unsubscribed. Deleting it would force any future consumer to either add per-connection subscription loops or reintroduce the registry plumbing later.
- **Pass a callback into `ConnectionRegistry.register`.** Rejected: it would push ingestion policy into the registry's public API and couple it to the service, defeating the registry's role as a transport-agnostic state hub.

### Consequences

- One subscription chain per connection, end to end. No duplicate parser invocations.
- Per-connection error context is preserved via an `onError` handler on the registry's per-connection `listen` (logs `[<conn.id>] stream error: ...` with the connection id in scope).
- `StationService.attach` enforces a single-attach contract via `assert`; calling it twice is a programming error.
- `_packetSourceFor` is now a private static helper on `StationService`; `main.dart` no longer carries transport-tagging logic.
- Future consumers of `registry.lines` need only `registry.lines.listen(...)` — no plumbing changes required.

---

## ADR-064: Inject `GeolocatorAdapter` for testable GPS access in `BeaconingService`

**Date:** 2026-04-26
**Status:** Accepted

### Context

`BeaconingService` (`lib/services/beaconing_service.dart`) had no service-level test coverage despite owning the timer state machine, mode transitions, smart-mode reschedule logic, and the `MissingPluginException → BeaconError.locationUnsupported` translation. PR 2 (#43) had already injected the `Clock` typedef so timer fires can be driven deterministically with `fake_async`, but five static `Geolocator.*` calls remained — `isLocationServiceEnabled`, `checkPermission`, `requestPermission`, `getCurrentPosition`, `getPositionStream` — and `package:geolocator` has no in-tree mocking helper that would work in a Dart-only `flutter test` (no platform channels, no method channel mocker).

### Decision

Introduce `lib/services/geolocator_adapter.dart`:

```dart
abstract class GeolocatorAdapter { /* the 5 methods above, signatures verbatim */ }
class RealGeolocatorAdapter implements GeolocatorAdapter { /* delegates 1:1 */ }
```

`BeaconingService` accepts `GeolocatorAdapter geo = const RealGeolocatorAdapter()` as a defaulted constructor parameter and replaces every `Geolocator.X(...)` call with `_geo.X(...)`. No translation, no remapping — the adapter is a thin pass-through. `MissingPluginException` continues to bubble up from each method exactly as it did from the static calls; the existing `try/catch` blocks in `_requestPosition` and `_startPositionStream` continue to translate it into `BeaconError.locationUnsupported`. Tests pass `FakeGeolocatorAdapter` (in `test/helpers/`) with controllable `serviceEnabled` / `permission` / `throwMissingPlugin` flags and a stream the test can `emitPosition(...)` into.

### Alternatives considered

- **`mockito` / `mocktail` over the geolocator API.** Rejected: the project is mock-free in services today (`test/services/bulletin_scheduler_test.dart` uses a hand-rolled fixture + recording subclass), and adding `mockito` for one service would create a stylistic inconsistency. A small hand-rolled adapter mirrors the `KissTncTransport` / `SecureCredentialStore` pattern already established.
- **Method-channel mock via `TestDefaultBinaryMessengerBinding`.** Rejected: would re-implement geolocator's wire protocol and bind us to its internal channel codec. Higher maintenance and lower clarity than a Dart-level seam.

### Consequences

- `BeaconingService` is now fully covered by `test/services/beaconing_service_test.dart` (12 cases): mode transitions, smart-mode reschedule (shorten-only), suspend/resume handoff, `onBeaconSent` fan-out, and `locationUnsupported` (single-attempt bounded, no retry storm).
- The `FakeGeolocatorAdapter` helper is the natural template for v0.20's wider widget-test sweep when GPS-dependent UI gets covered.
- No production wiring change — `lib/main.dart` continues to construct `BeaconingService(settings, tx, onBeaconSent: ...)` and the default `RealGeolocatorAdapter()` preserves identical runtime behavior.

---

## ADR-065: Pin `flutter_blue_plus` to v1.x (license incompatibility)

**Date:** 2026-04-26
**Status:** Accepted

### Context

`flutter_blue_plus` v2.0.0 (published on pub.dev as part of the 2.x line, current latest 2.2.1) was not an API migration. Its only changelog entry is *"[LICENSE] switch to FlutterBluePlus license."* The new "FlutterBluePlus License v1.3" is dual-tier:

- Free for personal use, registered nonprofits, and accredited educational institutions
- **Paid commercial license required for any for-profit use**, tiered by employee count (Starter 0–9, Team 10–29, Business 30–99, Enterprise 100+)
- Treats *"use of the Software during development, testing, or evaluation by a for-profit organization"* as commercial use
- No open-source-project exemption

Meridian APRS is **GPL v3**. GPL v3 §7 forbids adding restrictions to a covered work beyond GPL's own terms when distributing it as part of a derivative work; a downstream packager or contributor that is a for-profit organization would be required by the FBP license to obtain a paid commercial license, which is precisely the kind of additional restriction GPL v3 forbids. The two licenses cannot co-exist in a redistributed binary.

Issue #55 was filed during the v0.13-pre audit sweep based on the assumption that v2 was a normal API migration. v0.18 was scheduled to absorb that migration. The license discovery during pre-flight investigation reframed the work entirely.

### Decision

Pin `flutter_blue_plus` to `>=1.36.0 <2.0.0` in `pubspec.yaml`. Resolved version stays at `1.36.8` (BSD-3-Clause). Replace the plugin with a permissively licensed alternative in a dedicated pre-1.0 milestone (tracked at #114).

A one-line comment in `pubspec.yaml` references this ADR so the constraint is self-explaining.

### Alternatives considered

- **Migrate to FBP v2 under a paid commercial license.** Rejected. A purchased license authorizes the project's own development but does not relieve downstream recipients of the proprietary terms; GPL v3 redistribution to for-profit recipients remains impossible.
- **Fork `flutter_blue_plus` at the last BSD-3 commit and maintain it.** Rejected as the v0.18 mitigation. Maintaining a BLE plugin fork is a non-trivial commitment (Android / iOS / desktop platform code, future SDK targets, security fixes). Reserved as a fallback option within the #114 replacement milestone if no maintained alternative meets requirements.
- **Migrate immediately to `flutter_reactive_ble` (Apache-2.0) or `quick_blue` (MIT).** Rejected for v0.18 — the plugin swap touches the BLE scanner UI, the `BleDeviceAdapter` contract, MTU handling, notify subscription shape, and connect/autoConnect semantics; surface area is larger than the v0.18 budget and warrants its own milestone.

### Consequences

- No upstream fixes (iOS Core Bluetooth backend, Android 14+ permission refinements, security patches) reach Meridian past the v1.36.x line. The risk window grows the longer the pin holds.
- The `BleDeviceAdapter` interface in `lib/core/transport/ble_tnc_transport_impl.dart` already isolates the bulk of fbp from production code — when the replacement lands, the swap is concentrated there plus `lib/ui/widgets/ble_scanner_sheet.dart` and the `flutter_blue_plus_platform_interface 7.0.0` transitive.
- Replacement plugin work (#114) is a pre-1.0 blocker. v1.0 cannot ship on a deprecating dependency.
- This ADR is the canonical reference for any future contributor who notices the upper-bound constraint and wonders why we are not on the latest line.

### References

- Issue #55 (closed by the PR that landed this ADR)
- Issue #114 (replacement-plugin tracking, pre-1.0 blocker)
- pub.dev changelog: `https://pub.dev/packages/flutter_blue_plus/changelog`
- License text: `https://github.com/chipweinberger/flutter_blue_plus/blob/master/LICENSE.md`

---

## ADR-066: Standards-aware BLE-KISS naming and multi-family TNC support

**Date:** 2026-05-01
**Status:** Accepted

### Context

Until this change, `lib/core/transport/ble_constants.dart` exposed three constants — `kMobilinkdServiceUuid`, `kMobilinkdTxCharUuid`, `kMobilinkdRxCharUuid` — and the BLE scanner UI filtered to a single "Mobilinkd TNC4" preset. The naming implied a vendor-proprietary GATT service, but the UUID `00000001-ba2a-46c9-ae49-01b0961f68bb` is in fact the standardized [`hessu/aprs-specs` BLE-KISS API](https://github.com/hessu/aprs-specs/blob/master/BLE-KISS-API.md) shared by Mobilinkd TNC3/TNC4, PicoAPRS v4, B.B. Link adapter, RPC ESP32 trackers, CA2RXU LoRa trackers, and any future spec-compliant device. The "Mobilinkd-only" framing was misleading and unnecessarily limiting.

A second, older family also exists. The [`ge0rg/bluetoothle-tnc`](https://github.com/ge0rg/bluetoothle-tnc/blob/master/Bluetooth-LE-TNC.md) spec — Family B — is what BTECH UV-Pro firmware ≥ 0.7.11, Vero VR-N76 / VR-N7500, and Radioddity GA-5WB use for KISS-over-BLE (when KISS mode is enabled in the radio menu). KISS framing on the wire is identical across both families; only the GATT plumbing differs.

A user is bringing a BTECH UV-Pro online, and broader market support is on the v0.20 polish agenda regardless. Doing both — the rename and Family B support — together is cleaner than two staggered passes.

### Decision

Rename the constants to reflect the standard:
  - `kMobilinkdServiceUuid` → `kBleKissServiceUuid`
  - `kMobilinkdTxCharUuid` → `kBleKissNotifyCharUuid` (the host's RX, also corrects the inverted Tx/Rx naming the original constants used)
  - `kMobilinkdRxCharUuid` → `kBleKissWriteCharUuid` (the host's TX)

Add Family B constants alongside (`kBenshiKiss*`).

Introduce `BleKissFamily` enum and `BleKissProfile` value object so the transport, connection, and scanner can speak about the family explicitly. Add `bleKissFamilyForServiceUuids(...)` for resolving advertised UUIDs to a family.

Refactor `BleTncTransport` to autodetect the family at connect time from the discovered service list, with an optional `family` constructor hint when scan advertisement data already names it. The Mobilinkd-specific quirks — no `requestConnectionPriority`, no KISS init frames, no SETHARDWARE 0x06 — remain gated to all families conservatively until each is proven safe per-family on real hardware.

The scanner sheet drops the per-model dropdown in favour of a single "Show all Bluetooth devices" toggle; default scans pass both family service UUIDs to `FlutterBluePlus.startScan(withServices: ...)` so the OS performs advertisement filtering. A small `BleTncKnownDevice` registry in `lib/ui/widgets/` renders friendly labels and icons for known hardware (Mobilinkd TNC3/TNC4, PicoAPRS, B.B. Link, BTECH UV-Pro, Vero VR-N76/VR-N7500, Radioddity GA-5WB, RPC ESP32, CA2RXU).

`@Deprecated` aliases for the three old constant names remain for one release to soften the migration for any in-flight branches.

### Consequences

- BLE TNC support is no longer single-vendor. Users with Family B hardware can connect without code changes — the transport autodetects the family.
- The "Show all Bluetooth devices" toggle keeps a path for DIY ESP32 builds (Nordic UART) and troubleshooting; users still see those devices when the default filter excludes them.
- `BleConnection.connectToDevice` gained an optional `family` parameter. Callers that don't pass it (background reconnects from a persisted device id) still work — the transport autodetects.
- Family-specific quirks are now expressible. The current code intentionally applies Mobilinkd's conservative defaults to every family until per-family hardware data justifies relaxation; future ADRs will narrow this as we learn what each family actually tolerates.

### References

- `lib/core/transport/ble_constants.dart` — family enum, profiles, resolver
- `lib/core/transport/ble_tnc_transport_impl.dart` — autodetect on connect
- `lib/ui/widgets/ble_tnc_known_device.dart` — friendly-name registry
- `lib/ui/widgets/ble_scanner_sheet.dart` — multi-family default scan + advanced toggle
- [hessu/aprs-specs BLE-KISS API](https://github.com/hessu/aprs-specs/blob/master/BLE-KISS-API.md) — Family A spec
- [ge0rg/bluetoothle-tnc spec](https://github.com/ge0rg/bluetoothle-tnc/blob/master/Bluetooth-LE-TNC.md) — Family B spec
- [BTECH UV-Pro firmware 0.7.11 KISS announcement](https://baofengtech.com/btech-uv-pro-firmware-update-0-7-11-kiss-mode-now-built-in/)

