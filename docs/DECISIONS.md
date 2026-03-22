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