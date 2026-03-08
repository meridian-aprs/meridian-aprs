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
