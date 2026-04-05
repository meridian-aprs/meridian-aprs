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
- `FOREGROUND_SERVICE_CONNECTED_DEVICE` and `FOREGROUND_SERVICE_DATA_SYNC` added with `android:minSdkVersion="34"` guard — silently ignored on lower API levels.
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

